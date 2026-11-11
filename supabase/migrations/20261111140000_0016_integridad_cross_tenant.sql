-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 16: integridad cross-tenant y evidencia de revisión
-- Fecha: 2026-11-11
--
-- Problema:
--   1. Las FK de `empleado_id` validaban solo el id del perfil, no la empresa.
--      Un JWT con claims viejos (o una corrección con service_role) podía dejar
--      una jornada o una solicitud de la empresa A apuntando a un perfil de la
--      empresa B. La fila quedaba huérfana de su tenant.
--   2. `revisado_por` usaba ON DELETE SET NULL. Al borrar la cuenta del admin
--      que aprobó, la solicitud sobrevivía pero se perdía la evidencia de quién
--      la había revisado; solo quedaba la fecha.
--   3. `perfiles.empresa_id` se podía cambiar con historial vivo, dejando las
--      jornadas y solicitudes anteriores en una empresa distinta a la del
--      empleado.
--
-- Decisión:
--   1. `unique (empresa_id, id)` en `perfiles` como destino de las FK compuestas.
--   2. `(empresa_id, empleado_id)` en `jornadas` y `solicitudes_horas_extras`
--      referencia `perfiles (empresa_id, id)` con ON DELETE RESTRICT.
--   3. `(empresa_id, revisado_por)` en `solicitudes_horas_extras` referencia
--      `perfiles (empresa_id, id)` con ON DELETE RESTRICT. La revisión conserva
--      al revisor y la empresa; para dar de baja a una persona se desactiva su
--      perfil, no se borra la cuenta.
--
--   Las FK de empleado conservan ON DELETE RESTRICT (0012): el historial no se
--   borra y una transferencia entre empresas exige desactivar la cuenta y crear
--   una nueva, en lugar de reescribir el pasado.
--
-- Depende de 0004 (perfiles) y 0012 (retención del historial).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Destino único para las FK compuestas
-- -----------------------------------------------------------------------------
alter table public.perfiles
  add constraint perfiles_empresa_id_key unique (empresa_id, id);

comment on constraint perfiles_empresa_id_key on public.perfiles is
  'Permite que jornadas y solicitudes referencien al empleado y a su empresa en una sola FK, sin filas cross-tenant.';

-- -----------------------------------------------------------------------------
-- 2. Jornadas: el empleado debe pertenecer a la empresa de la jornada
-- -----------------------------------------------------------------------------
alter table public.jornadas
  drop constraint jornadas_empleado_id_fkey,
  add constraint jornadas_empleado_empresa_fkey
    foreign key (empresa_id, empleado_id)
    references public.perfiles (empresa_id, id)
    on delete restrict;

comment on constraint jornadas_empleado_empresa_fkey on public.jornadas is
  'El empleado de la jornada debe pertenecer a la misma empresa. ON DELETE RESTRICT conserva el historial laboral.';

-- -----------------------------------------------------------------------------
-- 3. Solicitudes: empleado y revisor en la misma empresa
-- -----------------------------------------------------------------------------
alter table public.solicitudes_horas_extras
  drop constraint solicitudes_horas_extras_empleado_id_fkey,
  add constraint solicitudes_empleado_empresa_fkey
    foreign key (empresa_id, empleado_id)
    references public.perfiles (empresa_id, id)
    on delete restrict,
  drop constraint solicitudes_horas_extras_revisado_por_fkey,
  add constraint solicitudes_revisado_por_empresa_fkey
    foreign key (empresa_id, revisado_por)
    references public.perfiles (empresa_id, id)
    on delete restrict;

comment on constraint solicitudes_empleado_empresa_fkey on public.solicitudes_horas_extras is
  'El especialista debe pertenecer a la misma empresa de la solicitud. ON DELETE RESTRICT conserva el historial.';
comment on constraint solicitudes_revisado_por_empresa_fkey on public.solicitudes_horas_extras is
  'El revisor debe pertenecer a la misma empresa y no se puede borrar mientras exista evidencia de su revisión.';

create index solicitudes_revisor_idx
  on public.solicitudes_horas_extras (empresa_id, revisado_por);
