-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 09: cierre de jornadas vencidas
-- Fecha: 2026-11-10
--
-- Problema:
--   La restricción jornadas_duracion_maxima (24 h) se evaluaba al cerrar. Si un
--   empleado olvidaba marcar la salida, al volver no podía cerrar la jornada
--   (el cierre usa clock_timestamp() y supera las 24 h) ni abrir una nueva
--   (el índice único de jornada abierta se lo impedía). Quedaba atrapado hasta
--   que un administrador corrigiera la fila con service_role.
--
-- Decisión:
--   La base de datos guarda el tiempo real trabajado, sin tope. Un turno
--   anómalo queda visible en el historial y el administrador puede corregirlo
--   con service_role. Es preferible un registro largo y auditable a una jornada
--   abierta permanente. Se conserva la validación salida_en > entrada_en.
--
-- Depende de 0005 (jornadas).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

alter table public.jornadas
  drop constraint jornadas_duracion_maxima;

comment on column public.jornadas.salida_en is
  'Salida real de la jornada. Sin tope de duración para no bloquear el cierre de turnos olvidados; el historial permite detectar anomalías.';
