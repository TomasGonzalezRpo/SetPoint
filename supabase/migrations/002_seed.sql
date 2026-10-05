-- Datos de ejemplo (opcional). Edita a tu gusto antes de ejecutar.
insert into canchas (nombre, ubicacion, superficie) values
  ('Cancha 1', 'Club', 'arcilla');

insert into paquetes (nombre, tipo, num_clases, precio, vigencia_dias) values
  ('4 clases individuales', 'individual', 4,  0, 30),
  ('8 clases individuales', 'individual', 8,  0, 60),
  ('4 clases pareja',       'pareja',     4,  0, 30),
  ('8 clases mixto',        'grupal',     8,  0, 60);
-- ⚠️ Cambia los precios (0) por los reales.
