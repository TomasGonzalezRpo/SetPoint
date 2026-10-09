-- =====================================================================
-- SetPoint — Tarifas y planes 2026 (COP)
-- Se puede ejecutar varias veces sin duplicar datos.
-- =====================================================================

-- Clase sin plan (por hora)
insert into tarifas (tipo, precio_hora) values
  ('individual',  67000),
  ('pareja',     100000),
  ('grupal',     120000)
on conflict (tipo) do update set precio_hora = excluded.precio_hora;

-- Planes mensuales (precio por plan; pareja/grupal = precio total del grupo)
insert into planes (tipo, nombre, minutos_semana, precio) values
  -- 01 Individual (1 persona)
  ('individual', 'Individual 1h/semana',    60,  235000),
  ('individual', 'Individual 2h/semana',   120,  450000),
  ('individual', 'Individual 3h/semana',   180,  610000),
  ('individual', 'Individual 4h/semana',   240,  750000),
  ('individual', 'Individual 6h/semana',   360, 1070000),
  ('individual', 'Individual 8h/semana',   480, 1250000),
  -- 02 En pareja (2 personas)
  ('pareja',     'Pareja 1h/semana',        60,  350000),
  ('pareja',     'Pareja 1.25h/semana',     75,  425000),
  ('pareja',     'Pareja 1.5h/semana',      90,  500000),
  ('pareja',     'Pareja 2h/semana',       120,  650000),
  ('pareja',     'Pareja 3h/semana',       180,  950000),
  -- 03 Grupal (3–5 personas)
  ('grupal',     'Grupal 1h/semana',        60,  415000),
  ('grupal',     'Grupal 2h/semana',       120,  785000),
  ('grupal',     'Grupal 3h/semana',       180, 1155000)
on conflict (tipo, minutos_semana) where activo do nothing;

-- Cancha por defecto (edítala)
insert into canchas (nombre)
select 'Cancha 1' where not exists (select 1 from canchas);
