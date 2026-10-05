-- =====================================================================
-- SetPoint — Esquema inicial
-- Ejecutar en Supabase: SQL Editor → New query → pegar → Run
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type tipo_clase        as enum ('individual', 'pareja', 'grupal');
create type estado_inscripcion as enum ('activa', 'finalizada', 'cancelada');
create type estado_clase      as enum ('programada', 'dada', 'falta_cobrada', 'falta_justificada', 'cancelada');
create type metodo_pago       as enum ('efectivo', 'transferencia', 'nequi', 'daviplata', 'otro');

-- ---------------------------------------------------------------------
-- Alumnos (un registro puede representar una pareja, ej. "Ana y Luis")
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
  nombre      text not null,
  ubicacion   text,
  superficie  text,               -- arcilla, dura, sintética...
  activa      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Paquetes (plantillas: "8 clases individuales")
-- ---------------------------------------------------------------------
create table paquetes (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,
  tipo          tipo_clase not null default 'individual',
  num_clases    int  not null check (num_clases > 0),
  precio        int  not null check (precio >= 0),        -- COP
  vigencia_dias int  not null default 60 check (vigencia_dias > 0),
  activo        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Inscripciones (paquete comprado por un alumno)
-- clases_total y precio se copian del paquete al momento de inscribir,
-- así cambiar un paquete no altera lo ya vendido.
-- ---------------------------------------------------------------------
create table inscripciones (
  id                uuid primary key default gen_random_uuid(),
  alumno_id         uuid not null references alumnos(id) on delete cascade,
  paquete_id        uuid references paquetes(id) on delete set null,
  tipo              tipo_clase not null,
  clases_total      int  not null check (clases_total > 0),
  clases_usadas     int  not null default 0,
  clases_restantes  int  generated always as (clases_total - clases_usadas) stored,
  precio            int  not null check (precio >= 0),
  fecha_inicio      date not null default current_date,
  fecha_vencimiento date not null,
  estado            estado_inscripcion not null default 'activa',
  created_at        timestamptz not null default now(),
  constraint usadas_validas check (clases_usadas between 0 and clases_total),
  constraint fechas_validas check (fecha_vencimiento >= fecha_inicio)
);
create index on inscripciones (alumno_id, estado);

-- ---------------------------------------------------------------------
-- Clases
-- Consumen paquete: 'dada' y 'falta_cobrada'.
-- inscripcion_id nulo = clase suelta (sin paquete).
-- ---------------------------------------------------------------------
create table clases (
  id             uuid primary key default gen_random_uuid(),
  alumno_id      uuid not null references alumnos(id) on delete cascade,
  inscripcion_id uuid references inscripciones(id) on delete set null,
  cancha_id      uuid references canchas(id) on delete set null,
  tipo           tipo_clase not null default 'individual',
  fecha          date not null,
  hora           time not null,
  duracion_min   int  not null default 60 check (duracion_min > 0),
  estado         estado_clase not null default 'dada',
  notas          text,
  created_at     timestamptz not null default now()
);
create index on clases (fecha);
create index on clases (alumno_id, fecha desc);
create index on clases (inscripcion_id);

-- ---------------------------------------------------------------------
-- Pagos
-- ---------------------------------------------------------------------
create table pagos (
  id             uuid primary key default gen_random_uuid(),
  alumno_id      uuid not null references alumnos(id) on delete cascade,
  inscripcion_id uuid references inscripciones(id) on delete set null,
  monto          int  not null check (monto > 0),          -- COP
  metodo         metodo_pago not null default 'efectivo',
  fecha          date not null default current_date,
  notas          text,
  created_at     timestamptz not null default now()
);
create index on pagos (alumno_id, fecha desc);
create index on pagos (fecha);

-- =====================================================================
-- Lógica: mantener clases_usadas y estado de la inscripción
-- =====================================================================
create or replace function recalcular_inscripcion(p_id uuid)
returns void language plpgsql as $$
begin
  if p_id is null then return; end if;

  update inscripciones i
     set clases_usadas = sub.usadas,
         estado = case
                    when i.estado = 'cancelada'           then 'cancelada'
                    when sub.usadas >= i.clases_total     then 'finalizada'
                    else 'activa'
                  end::estado_inscripcion
    from (
      select count(*)::int as usadas
        from clases
       where inscripcion_id = p_id
         and estado in ('dada', 'falta_cobrada')
    ) sub
   where i.id = p_id;
end $$;

create or replace function trg_clases_recalcular()
returns trigger language plpgsql as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform recalcular_inscripcion(old.inscripcion_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    if tg_op = 'INSERT' or new.inscripcion_id is distinct from old.inscripcion_id then
      perform recalcular_inscripcion(new.inscripcion_id);
    elsif new.estado is distinct from old.estado then
      perform recalcular_inscripcion(new.inscripcion_id);
    end if;
  end if;
  return null;
end $$;

create trigger clases_recalcular
after insert or update or delete on clases
for each row execute function trg_clases_recalcular();

-- =====================================================================
-- Vistas
-- =====================================================================

-- Inscripciones con lo pagado y el saldo pendiente
create or replace view v_inscripciones with (security_invoker = true) as
select i.*,
       coalesce(p.pagado, 0)                 as total_pagado,
       i.precio - coalesce(p.pagado, 0)      as saldo,
       (i.estado = 'activa' and i.fecha_vencimiento < current_date) as vencida
  from inscripciones i
  left join (
    select inscripcion_id, sum(monto)::int as pagado
      from pagos
     where inscripcion_id is not null
     group by inscripcion_id
  ) p on p.inscripcion_id = i.id;

-- Resumen por alumno para la lista
create or replace view v_alumnos_resumen with (security_invoker = true) as
select a.*,
       act.id                as inscripcion_activa_id,
       act.tipo              as tipo_activo,
       act.clases_restantes,
       act.fecha_vencimiento,
       coalesce(tot.total_clases, 0)  as total_clases,
       coalesce(pag.total_pagado, 0)  as total_pagado,
       (act.clases_restantes is not null and act.clases_restantes <= 3) as por_vencer
  from alumnos a
  left join lateral (
    select i.id, i.tipo, i.clases_restantes, i.fecha_vencimiento
      from inscripciones i
     where i.alumno_id = a.id and i.estado = 'activa'
     order by i.fecha_inicio, i.created_at
     limit 1
  ) act on true
  left join (
    select alumno_id, count(*)::int as total_clases
      from clases where estado in ('dada', 'falta_cobrada')
     group by alumno_id
  ) tot on tot.alumno_id = a.id
  left join (
    select alumno_id, sum(monto)::int as total_pagado
      from pagos group by alumno_id
  ) pag on pag.alumno_id = a.id;

-- =====================================================================
-- Seguridad: RLS activado sin políticas.
-- Solo el backend (service_role) puede leer/escribir.
-- =====================================================================
alter table alumnos       enable row level security;
alter table canchas       enable row level security;
alter table paquetes      enable row level security;
alter table inscripciones enable row level security;
alter table clases        enable row level security;
alter table pagos         enable row level security;

revoke all on v_inscripciones, v_alumnos_resumen from anon, authenticated;
