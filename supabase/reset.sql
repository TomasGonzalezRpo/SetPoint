-- =====================================================================
-- SetPoint — RESET: borra TODO el esquema de SetPoint (tablas y datos).
-- Úsalo solo para reinstalar desde cero. Después ejecuta, en orden:
--   migrations/001_initial.sql  →  migrations/002_seed.sql
-- =====================================================================

drop view  if exists v_dashboard, v_alumnos_resumen, v_inscripciones cascade;

drop table if exists pagos, clases, inscripciones, planes, paquetes,
                     tarifas, canchas, alumnos cascade;

drop function if exists recalcular_inscripcion(uuid)                       cascade;
drop function if exists trg_clases_recalcular()                            cascade;
drop function if exists trg_clases_validar()                               cascade;
drop function if exists trg_inscripciones_defaults()                       cascade;
drop function if exists inscripcion_para_clase(uuid, tipo_clase, date, int) cascade;
drop function if exists es_cobrable(estado_clase)                          cascade;
drop function if exists hoy()                                              cascade;

drop type if exists metodo_pago, estado_clase, estado_inscripcion, tipo_clase cascade;
