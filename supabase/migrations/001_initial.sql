-- =====================================================================
-- SetPoint — Esquema inicial
-- Ejecutar en Supabase: SQL Editor → New query → pegar → Run
--
-- Modelo de negocio:
--   • Planes mensuales por horas/semana (Individual, Pareja, Grupal).
--   • El saldo del plan se maneja en MINUTOS (soporta 1.25h, 1.5h...).
--     Un mes = 4 semanas → minutos del plan = minutos_semana × 4.
--   • Clase sin plan ("suelta") = tarifa por hora según tipo × duración.
--   • Precios en COP enteros (235000 = $235.000).
--   • Fechas "de negocio" en hora de Colombia (Supabase corre en UTC).
--   • Nada con historial se borra: alumnos/planes se desactivan (activo=false)
--     e inscripciones se cancelan (estado='cancelada').
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type tipo_clase         as enum ('individual', 'pareja', 'grupal');
create type estado_inscripcion as enum ('activa', 'finalizada', 'cancelada');
create type estado_clase       as enum ('programada', 'dada', 'falta_cobrada', 'falta_justificada', 'cancelada');
create type metodo_pago        as enum ('efectivo', 'transferencia', 'nequi', 'daviplata', 'otro');

-- Fecha de hoy en Colombia (current_date sería UTC: después de las 7 p. m. ya es "mañana")
create or replace function hoy()
returns date language sql stable as $$
  select (now() at time zone 'America/Bogota')::date
$$;

-- ¿Este estado consume saldo / se cobra?
create or replace function es_cobrable(e estado_clase)
returns boolean language sql immutable as $$
  select e in ('dada', 'falta_cobrada')
$$;

-- ---------------------------------------------------------------------
-- Alumnos (un registro puede representar una pareja o un grupo)
-- ---------------------------------------------------------------------
create table alumnos (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (length(trim(nombre)) > 0),
  telefono    text,
  notas       text,
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Canchas
-- ---------------------------------------------------------------------
create table canchas (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (length(trim(nombre)) > 0),
  ubicacion   text,
  superficie  text,
  activa      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Tarifa por hora para clases sueltas
-- ---------------------------------------------------------------------
create table tarifas (
  tipo        tipo_clase primary key,
  precio_hora int not null check (precio_hora >= 0)
);

-- ---------------------------------------------------------------------
-- Planes (catálogo: "Individual 2h/semana — $450.000/mes")
-- Para cambiar un precio: desactiva el plan viejo y crea uno nuevo.
-- ---------------------------------------------------------------------
create table planes (
  id              uuid primary key default gen_random_uuid(),
  tipo            tipo_clase not null,
  nombre          text not null check (length(trim(nombre)) > 0),
  minutos_semana  int  not null check (minutos_semana > 0),
  minutos_mes     int  generated always as (minutos_semana * 4) stored,
  precio          int  not null check (precio >= 0),
  vigencia_dias   int  not null default 30 check (vigencia_dias > 0),
  activo          boolean not null default true,
  created_at      timestamptz not null default now()
);
-- Solo un plan ACTIVO por tipo y horas (los inactivos quedan como historial)
create unique index planes_activo_unico on planes (tipo, minutos_semana) where activo;

-- ---------------------------------------------------------------------
-- Inscripciones (plan comprado por un alumno)
-- Basta con enviar alumno_id + plan_id: el trigger copia tipo, minutos,
-- precio y calcula el vencimiento. Cambiar el catálogo no altera lo vendido.
-- ---------------------------------------------------------------------
create table inscripciones (
  id                uuid primary key default gen_random_uuid(),
  alumno_id         uuid not null references alumnos(id) on delete restrict,
  plan_id           uuid references planes(id) on delete restrict,
  tipo              tipo_clase not null,
  minutos_semana    int  not null check (minutos_semana > 0),
  minutos_total     int  not null check (minutos_total > 0),
  minutos_usados    int  not null default 0 check (minutos_usados >= 0),
  minutos_restantes int  generated always as (minutos_total - minutos_usados) stored,
  precio            int  not null check (precio >= 0),
  fecha_inicio      date not null default hoy(),
  fecha_vencimiento date not null,
  estado            estado_inscripcion not null default 'activa',
  notas             text,
  created_at        timestamptz not null default now(),
  constraint fechas_validas  check (fecha_vencimiento >= fecha_inicio),
  constraint saldo_suficiente check (minutos_usados <= minutos_total)
);
create index on inscripciones (alumno_id, estado);

create or replace function trg_inscripciones_defaults()
returns trigger language plpgsql as $$
declare
  p planes;
begin
  if new.plan_id is not null then
    select * into p from planes where id = new.plan_id;
    if not found then
      raise exception 'El plan no existe' using errcode = 'foreign_key_violation';
    end if;
    new.tipo           := coalesce(new.tipo,           p.tipo);
    new.minutos_semana := coalesce(new.minutos_semana, p.minutos_semana);
    new.minutos_total  := coalesce(new.minutos_total,  p.minutos_mes);
    new.precio         := coalesce(new.precio,         p.precio);
    new.fecha_inicio   := coalesce(new.fecha_inicio,   hoy());
    new.fecha_vencimiento := coalesce(new.fecha_vencimiento,
                                      new.fecha_inicio + p.vigencia_dias - 1);
  end if;
  -- Sin plan (inscripción manual): minutos_total por defecto = 4 semanas
  new.minutos_total := coalesce(new.minutos_total, new.minutos_semana * 4);
  new.fecha_inicio  := coalesce(new.fecha_inicio, hoy());
  new.fecha_vencimiento := coalesce(new.fecha_vencimiento, new.fecha_inicio + 29);
  return new;
end $$;

create trigger inscripciones_defaults
before insert on inscripciones
for each row execute function trg_inscripciones_defaults();

-- ---------------------------------------------------------------------
-- Clases
-- Con inscripcion_id → descuenta minutos del plan si es 'dada' o 'falta_cobrada'.
-- Sin inscripcion_id → clase suelta: `precio` se calcula con la tarifa.
-- ---------------------------------------------------------------------
create table clases (
  id             uuid primary key default gen_random_uuid(),
  alumno_id      uuid not null references alumnos(id) on delete restrict,
  inscripcion_id uuid references inscripciones(id) on delete restrict,
  cancha_id      uuid references canchas(id) on delete set null,
  tipo           tipo_clase not null default 'individual',
  fecha          date not null default hoy(),
  hora           time not null,
  duracion_min   int  not null default 60 check (duracion_min between 15 and 480),
  estado         estado_clase not null default 'dada',
  precio         int  check (precio >= 0),
  notas          text,
  created_at     timestamptz not null default now(),
  constraint precio_solo_sueltas check (inscripcion_id is null or precio is null)
);
create index on clases (fecha);
create index on clases (alumno_id, fecha desc);
create index on clases (inscripcion_id);

-- Antes de guardar: coherencia con la inscripción y precio de sueltas
create or replace function trg_clases_validar()
returns trigger language plpgsql as $$
declare
  i inscripciones;
begin
  if new.inscripcion_id is not null then
    select * into i from inscripciones where id = new.inscripcion_id;
    if i.alumno_id <> new.alumno_id then
      raise exception 'La inscripción no pertenece a este alumno'
        using errcode = 'check_violation';
    end if;
    if i.estado = 'cancelada' then
      raise exception 'La inscripción está cancelada'
        using errcode = 'check_violation';
    end if;
    new.tipo   := i.tipo;   -- la clase hereda el tipo del plan
    new.precio := null;     -- se paga con el plan
  elsif es_cobrable(new.estado) and new.precio is null then
    select round(t.precio_hora * new.duracion_min / 60.0)::int
      into new.precio
      from tarifas t where t.tipo = new.tipo;
  end if;
  return new;
end $$;

create trigger clases_validar
before insert or update on clases
for each row execute function trg_clases_validar();

-- ---------------------------------------------------------------------
-- Pagos
-- ---------------------------------------------------------------------
create table pagos (
  id             uuid primary key default gen_random_uuid(),
  alumno_id      uuid not null references alumnos(id) on delete restrict,
  inscripcion_id uuid references inscripciones(id) on delete restrict,
  clase_id       uuid references clases(id) on delete restrict,
  monto          int  not null check (monto > 0),
  metodo         metodo_pago not null default 'efectivo',
  fecha          date not null default hoy(),
  notas          text,
  created_at     timestamptz not null default now()
);
create index on pagos (alumno_id, fecha desc);
create index on pagos (fecha);

-- =====================================================================
-- Lógica: mantener minutos_usados y estado de la inscripción
-- Si una clase deja el plan en negativo, el CHECK saldo_suficiente
-- rechaza la operación completa (no se guarda la clase).
-- =====================================================================
create or replace function recalcular_inscripcion(p_id uuid)
returns void language plpgsql as $$
declare
  v_usados int;
  v_total  int;
begin
  if p_id is null then return; end if;

  select coalesce(sum(duracion_min), 0)::int into v_usados
    from clases
   where inscripcion_id = p_id and es_cobrable(estado);

  select minutos_total into v_total from inscripciones where id = p_id for update;
  if v_usados > v_total then
    raise exception 'Saldo insuficiente: el plan tiene % min y quedaría con % min usados', v_total, v_usados
      using errcode = 'check_violation';
  end if;

  update inscripciones i
     set minutos_usados = sub.usados,
         estado = case
                    when i.estado = 'cancelada'        then 'cancelada'
                    when sub.usados >= i.minutos_total then 'finalizada'
                    else 'activa'
                  end::estado_inscripcion
    from (select v_usados as usados) sub
   where i.id = p_id;
end $$;

create or replace function trg_clases_recalcular()
returns trigger language plpgsql as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform recalcular_inscripcion(old.inscripcion_id);
  end if;
  if tg_op = 'INSERT'
     or (tg_op = 'UPDATE' and (new.inscripcion_id is distinct from old.inscripcion_id
                               or new.estado       is distinct from old.estado
                               or new.duracion_min is distinct from old.duracion_min)) then
    perform recalcular_inscripcion(new.inscripcion_id);
  end if;
  return null;
end $$;

create trigger clases_recalcular
after insert or update or delete on clases
for each row execute function trg_clases_recalcular();

-- Inscripción que debe usar una clase nueva: la activa más antigua del
-- alumno y tipo, vigente en esa fecha y con saldo suficiente. NULL = suelta.
create or replace function inscripcion_para_clase(
  p_alumno uuid, p_tipo tipo_clase, p_fecha date, p_minutos int
) returns uuid language sql stable as $$
  select id
    from inscripciones
   where alumno_id = p_alumno
     and tipo      = p_tipo
     and estado    = 'activa'
     and p_fecha between fecha_inicio and fecha_vencimiento
     and minutos_restantes >= p_minutos
   order by fecha_vencimiento, created_at
   limit 1
$$;

-- =====================================================================
-- Vistas
-- =====================================================================

-- Inscripciones con lo pagado, saldo de dinero y si ya venció
create or replace view v_inscripciones with (security_invoker = true) as
select i.*,
       coalesce(p.pagado, 0)            as total_pagado,
       i.precio - coalesce(p.pagado, 0) as saldo,
       (i.estado = 'activa' and i.fecha_vencimiento < hoy()) as vencida
  from inscripciones i
  left join (
    select inscripcion_id, sum(monto)::int as pagado
      from pagos where inscripcion_id is not null
     group by inscripcion_id
  ) p on p.inscripcion_id = i.id;

-- Resumen por alumno (lista de alumnos, ficha y alertas)
--   minutos_disponibles: suma de todas sus inscripciones activas y vigentes
--   deuda: (planes no cancelados + clases sueltas cobrables) − pagos
--   estado_plan: 'al_dia' | 'por_vencer' (≤ 1 semana de horas o vence en ≤ 7 días)
--                | 'sin_plan' (no tiene plan activo y vigente → renovar)
create or replace view v_alumnos_resumen with (security_invoker = true) as
select a.*,
       act.id                              as inscripcion_activa_id,
       act.tipo                            as tipo_activo,
       act.minutos_semana,
       act.fecha_vencimiento,
       coalesce(disp.minutos_disponibles, 0) as minutos_disponibles,
       coalesce(tot.minutos_totales, 0)    as minutos_totales,
       coalesce(pag.total_pagado, 0)       as total_pagado,
       coalesce(cob.total_cobrado, 0) - coalesce(pag.total_pagado, 0) as deuda,
       case
         when act.id is null then 'sin_plan'
         when coalesce(disp.minutos_disponibles, 0) <= act.minutos_semana
           or act.fecha_vencimiento <= hoy() + 7 then 'por_vencer'
         else 'al_dia'
       end as estado_plan
  from alumnos a
  left join lateral (
    select i.id, i.tipo, i.minutos_semana, i.fecha_vencimiento
      from inscripciones i
     where i.alumno_id = a.id and i.estado = 'activa' and i.fecha_vencimiento >= hoy()
     order by i.fecha_vencimiento, i.created_at
     limit 1
  ) act on true
  left join (
    select alumno_id, sum(minutos_restantes)::int as minutos_disponibles
      from inscripciones
     where estado = 'activa' and fecha_vencimiento >= hoy()
     group by alumno_id
  ) disp on disp.alumno_id = a.id
  left join (
    select alumno_id, sum(duracion_min)::int as minutos_totales
      from clases where es_cobrable(estado)
     group by alumno_id
  ) tot on tot.alumno_id = a.id
  left join (
    select alumno_id, sum(monto)::int as total_pagado
      from pagos group by alumno_id
  ) pag on pag.alumno_id = a.id
  left join (
    select alumno_id, sum(v)::int as total_cobrado from (
      select alumno_id, precio as v from inscripciones where estado <> 'cancelada'
      union all
      select alumno_id, precio from clases
       where inscripcion_id is null and es_cobrable(estado) and precio is not null
    ) x group by alumno_id
  ) cob on cob.alumno_id = a.id;

-- Números del Dashboard (una sola fila)
create or replace view v_dashboard with (security_invoker = true) as
select
  (select count(*) from alumnos where activo)::int                         as alumnos_activos,
  (select count(*) from clases where fecha = hoy()
                                  and estado <> 'cancelada')::int          as clases_hoy,
  (select count(*) from v_alumnos_resumen where activo and estado_plan = 'por_vencer')::int as alumnos_por_vencer,
  (select count(*) from v_alumnos_resumen where activo and estado_plan = 'sin_plan')::int   as alumnos_sin_plan,
  (select coalesce(sum(monto), 0) from pagos
    where fecha >= date_trunc('month', hoy())::date)::int                  as ingresos_mes,
  (select coalesce(sum(duracion_min), 0) from clases
    where es_cobrable(estado)
      and fecha >= date_trunc('month', hoy())::date)::int                  as minutos_mes,
  (select coalesce(sum(greatest(deuda, 0)), 0) from v_alumnos_resumen)::int as deuda_total;

-- =====================================================================
-- Seguridad
-- RLS activado sin políticas: solo el backend (service_role) accede.
-- Supabase da permisos a anon/authenticated por defecto: se quitan.
-- =====================================================================
alter table alumnos       enable row level security;
alter table canchas       enable row level security;
alter table tarifas       enable row level security;
alter table planes        enable row level security;
alter table inscripciones enable row level security;
alter table clases        enable row level security;
alter table pagos         enable row level security;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant  execute on all functions in schema public to service_role;
