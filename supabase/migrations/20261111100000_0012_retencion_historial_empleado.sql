-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 12: retención del historial laboral
-- Fecha: 2026-11-11
--
-- Problema:
--   `jornadas.empleado_id` y `solicitudes_horas_extras.empleado_id` referencian
--   `public.perfiles` con ON DELETE CASCADE. A su vez, `public.perfiles` se
--   elimina en cascada al borrar `auth.users`. Por tanto, borrar una cuenta
--   eliminaba en silencio todas sus jornadas y solicitudes, incluida la
--   evidencia de quién aprobó o rechazó cada solicitud.
--
-- Decisión:
--   ON DELETE RESTRICT. La baja de personal se hace desactivando el perfil
--   (`public.perfiles.activo = false`), que ya bloquea escrituras y revoca la
--   lectura del equipo. El historial se conserva y sigue visible para el
--   administrador. Si se necesita borrar una cuenta sin historial, service_role
--   puede hacerlo porque la cascada no encuentra filas dependientes.
--
-- Depende de 0004 (perfiles), 0005 (jornadas) y 0006 (solicitudes).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Jornadas: el historial no se borra con el perfil
-- -----------------------------------------------------------------------------
alter table public.jornadas
  drop constraint jornadas_empleado_id_fkey,
  add constraint jornadas_empleado_id_fkey
    foreign key (empleado_id) references public.perfiles (id)
    on delete restrict;

comment on column public.jornadas.empleado_id is
  'Perfil del empleado. Por defecto auth.uid(); el cliente no puede elegir a otra persona. ON DELETE RESTRICT conserva el historial: para dar de baja se desactiva el perfil.';
comment on constraint jornadas_empleado_id_fkey on public.jornadas is
  'Impide borrar un perfil con jornadas: el historial laboral es evidencia y no se elimina en cascada.';

-- -----------------------------------------------------------------------------
-- 2. Solicitudes: la evidencia de la revisión tampoco se borra
-- -----------------------------------------------------------------------------
alter table public.solicitudes_horas_extras
  drop constraint solicitudes_horas_extras_empleado_id_fkey,
  add constraint solicitudes_horas_extras_empleado_id_fkey
    foreign key (empleado_id) references public.perfiles (id)
    on delete restrict;

comment on column public.solicitudes_horas_extras.empleado_id is
  'Perfil del especialista. Por defecto auth.uid(); el cliente no puede elegir a otra persona. ON DELETE RESTRICT conserva el historial: para dar de baja se desactiva el perfil.';
comment on constraint solicitudes_horas_extras_empleado_id_fkey on public.solicitudes_horas_extras is
  'Impide borrar un perfil con solicitudes: el historial de horas extras es evidencia y no se elimina en cascada.';
