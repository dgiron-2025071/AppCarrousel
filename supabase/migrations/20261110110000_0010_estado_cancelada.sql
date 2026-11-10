-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 10: estado `cancelada`
-- Fecha: 2026-11-10
--
-- Problema:
--   Una solicitud de horas extras enviada por error (rango equivocado, parque
--   incorrecto, duplicada) no tenía salida: el especialista no podía borrarla
--   ni retirarla y quedaba pendiente hasta que un administrador la rechazara.
--
-- Decisión:
--   Se agrega el estado `cancelada` al ciclo de vida. El especialista podrá
--   retirar únicamente su propia solicitud mientras siga pendiente. El
--   historial se conserva (no hay DELETE) y el administrador deja de poder
--   revisarla.
--
-- Nota:
--   PostgreSQL no permite usar un valor de enum nuevo dentro de la misma
--   transacción que lo agrega. Por eso el valor se crea aquí y las políticas y
--   el trigger que lo usan viven en la migración 0011.
--
-- Ejecución local: supabase db reset
-- =============================================================================

alter type public.estado_solicitud add value if not exists 'cancelada';

comment on type public.estado_solicitud is
  'Ciclo de vida de una solicitud de horas extras: pendiente, aprobada, rechazada o cancelada por el especialista.';
