-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 11: retiro de solicitudes propias
-- Fecha: 2026-11-10
--
-- Permite que el especialista retire una solicitud de horas extras mientras
-- siga pendiente. La cancelación:
--   - solo la puede hacer el dueño de la solicitud;
--   - no puede aplicarse a una solicitud ya aprobada, rechazada o cancelada;
--   - conserva la fila (historial auditable), sin DELETE;
--   - deja `revisado_por` en NULL y usa `revisado_en` como marca de cierre;
--   - impide que el administrador la apruebe o rechace después.
--
-- Depende de 0006 (solicitudes) y 0010 (valor `cancelada`).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trigger de cierre: revisión administrativa o retiro del especialista
-- -----------------------------------------------------------------------------
create or replace function private.solicitudes_set_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.estado is distinct from old.estado then
    -- Una solicitud cerrada no vuelve a pendiente ni cambia de decisión.
    if old.estado <> 'pendiente' then
      raise exception 'Una solicitud cerrada no puede cambiar de estado'
        using errcode = '23514';
    end if;

    if new.estado = 'cancelada' then
      -- Solo el dueño puede retirarla; el RLS ya lo limita, pero el trigger
      -- deja la regla explícita y protege futuras políticas.
      if old.empleado_id <> auth.uid() then
        raise exception 'Solo el especialista puede retirar su solicitud'
          using errcode = '42501';
      end if;

      new.revisado_por := null;
      new.revisado_en := now();
      new.comentario_admin := null;
    else
      new.revisado_por := auth.uid();
      new.revisado_en := now();
    end if;
  else
    -- Sin cambio de estado solo se permite ajustar el comentario de una
    -- solicitud revisada; la firma original se conserva.
    new.revisado_por := old.revisado_por;
    new.revisado_en := old.revisado_en;
  end if;

  return new;
end;
$$;

comment on function private.solicitudes_set_revision() is
  'Firma la revisión del admin o el retiro del especialista, e impide reabrir una solicitud cerrada.';

revoke all on function private.solicitudes_set_revision() from public;

-- -----------------------------------------------------------------------------
-- 2. RLS: el especialista retira su propia solicitud pendiente
-- -----------------------------------------------------------------------------
create policy solicitudes_update_propia_cancelar
  on public.solicitudes_horas_extras
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and empleado_id = (select auth.uid())
    and estado = 'pendiente'
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and empleado_id = (select auth.uid())
    and estado = 'cancelada'
    and revisado_por is null
    and revisado_en is not null
    and comentario_admin is null
  );

comment on policy solicitudes_update_propia_cancelar on public.solicitudes_horas_extras is
  'El especialista solo puede cambiar su propia solicitud pendiente a cancelada; no puede aprobarla ni editarla.';

comment on column public.solicitudes_horas_extras.revisado_por is
  'Admin que aprobó o rechazó. Queda NULL cuando el especialista retira su solicitud.';
comment on column public.solicitudes_horas_extras.revisado_en is
  'Momento en que la solicitud se cerró: revisión del admin o retiro del especialista.';
