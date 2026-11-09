-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 08: revocación inmediata de lectura para admin inactivo
-- Fecha: 2026-11-09
--
-- Problema:
--   La migración 0007 bloquea la escritura de un perfil inactivo, pero un
--   administrador desactivado conservaba la lectura del subárbol hasta que su
--   JWT expirara (hasta una hora). La desactivación debe surtir efecto de
--   inmediato en la base de datos.
--
-- Cambios:
--   1. Un admin inactivo solo ve su propio perfil, sus propias jornadas y sus
--      propias solicitudes. Pierde el acceso de lectura al equipo.
--   2. Un empleado inactivo conserva la lectura de su propio perfil e
--      historial (no se le oculta su información personal).
--
-- Depende de 0007 (private.perfil_propio_activo).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Jornadas: el alcance de equipo exige un admin activo
-- -----------------------------------------------------------------------------
drop policy jornadas_select_propia_o_equipo on public.jornadas;

create policy jornadas_select_propia_o_equipo
  on public.jornadas
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      empleado_id = (select auth.uid())
      or (
        (select private.perfil_propio_activo())
        and private.perfil_en_alcance(empleado_id)
      )
    )
  );

comment on policy jornadas_select_propia_o_equipo on public.jornadas is
  'El empleado ve sus jornadas; un admin activo ve las de su subárbol. Un admin inactivo pierde el acceso al equipo.';

-- -----------------------------------------------------------------------------
-- 2. Solicitudes: el alcance de equipo exige un admin activo
-- -----------------------------------------------------------------------------
drop policy solicitudes_select_propia_o_equipo on public.solicitudes_horas_extras;

create policy solicitudes_select_propia_o_equipo
  on public.solicitudes_horas_extras
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      empleado_id = (select auth.uid())
      or (
        (select private.perfil_propio_activo())
        and private.perfil_en_alcance(empleado_id)
      )
    )
  );

comment on policy solicitudes_select_propia_o_equipo on public.solicitudes_horas_extras is
  'El especialista ve sus solicitudes; un admin activo ve las de su subárbol. Un admin inactivo pierde el acceso al equipo.';

-- -----------------------------------------------------------------------------
-- 3. Perfiles: el alcance de equipo exige un admin activo
-- -----------------------------------------------------------------------------
drop policy perfiles_select_propio_o_equipo on public.perfiles;

create policy perfiles_select_propio_o_equipo
  on public.perfiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or (
      empresa_id = (select private.current_empresa_id())
      and (select private.es_admin())
      and (select private.perfil_propio_activo())
      and private.centro_en_alcance(centro_costo_id)
    )
  );

comment on policy perfiles_select_propio_o_equipo on public.perfiles is
  'Cada usuario ve su perfil; un admin activo ve además los perfiles de su subárbol. Un admin inactivo solo ve el suyo.';
