-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 18: coherencia de la revisión y solicitudes sin solape
-- Fecha: 2026-11-12
--
-- Problema:
--   1. `solicitudes_revision_coherente` solo exigía `revisado_en` para todo
--      estado distinto de `pendiente`. Con `service_role` (o una corrección
--      manual) se podía guardar una solicitud `aprobada`/`rechazada` sin la
--      firma de quién la revisó, o una `cancelada` con un revisor que nunca
--      participó. La evidencia de auditoría quedaba ambigua.
--   2. Un especialista podía enviar dos solicitudes con rangos solapados y el
--      administrador podía aprobar ambas, duplicando las horas extras.
--
-- Decisión:
--   1. Se reemplaza la restricción por una que exige:
--      - `pendiente`: sin revisor, sin fecha de cierre y sin comentario.
--      - `cancelada`: sin revisor, con fecha de cierre y sin comentario.
--      - `aprobada`/`rechazada`: con revisor, con fecha de cierre.
--   2. Se agrega una restricción de exclusión GiST por empleado y por rango
--      `[inicio, fin)` que solo considera solicitudes `pendiente` o
--      `aprobada`. Dos solicitudes vivas no pueden solaparse; una rechazada o
--      cancelada libera el rango para que el especialista lo corrija y lo
--      vuelva a enviar.
--
--   El toque de rangos contiguos (`fin = siguiente inicio`) no es solape.
--
-- Depende de 0006 (solicitudes), 0010 (`cancelada`) y 0016 (retención del
-- revisor).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Soporte GiST para comparar uuid por igualdad
-- -----------------------------------------------------------------------------
create extension if not exists btree_gist with schema extensions;

-- -----------------------------------------------------------------------------
-- 2. Coherencia estricta de la revisión
-- -----------------------------------------------------------------------------
alter table public.solicitudes_horas_extras
  drop constraint solicitudes_revision_coherente,
  add constraint solicitudes_revision_coherente check (
    (
      estado = 'pendiente'
      and revisado_por is null
      and revisado_en is null
      and comentario_admin is null
    )
    or (
      estado = 'cancelada'
      and revisado_por is null
      and revisado_en is not null
      and comentario_admin is null
    )
    or (
      estado in ('aprobada', 'rechazada')
      and revisado_por is not null
      and revisado_en is not null
    )
  );

comment on constraint solicitudes_revision_coherente on public.solicitudes_horas_extras is
  'Pendiente no tiene revisor ni comentario; cancelada cierra sin revisor; aprobada y rechazada exigen la firma del revisor.';

-- -----------------------------------------------------------------------------
-- 3. Una sola solicitud viva por rango y empleado
-- -----------------------------------------------------------------------------
alter table public.solicitudes_horas_extras
  add constraint solicitudes_sin_solape
  exclude using gist (
    empleado_id with =,
    tstzrange(inicio, fin, '[)') with &&
  ) where (estado in ('pendiente', 'aprobada'));

comment on constraint solicitudes_sin_solape on public.solicitudes_horas_extras is
  'Un especialista no puede tener dos solicitudes pendientes o aprobadas con rangos solapados. Rechazadas y canceladas liberan el rango.';
