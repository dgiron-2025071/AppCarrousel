-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 20: la revisión exige un administrador activo
-- Fecha: 2026-11-12
--
-- Problema:
--   `0019` valida que `revisado_por` sea un perfil `admin` de la misma empresa,
--   pero no exige que siga activo. La baja de personal se hace desactivando
--   `public.perfiles.activo`; un admin dado de baja conserva el rol en su fila y
--   `service_role` podía registrarle una revisión nueva. La firma dejaba de
--   representar a alguien habilitado para decidir.
--
-- Decisión:
--   El trigger de revisión exige además `perfiles.activo = true`. Las filas
--   históricas no se tocan: solo se valida al insertar o cuando cambia el
--   revisor, así que desactivar a un admin no invalida las revisiones que ya
--   firmó. La comprobación corre con `service_role` y sin RLS, igual que la de
--   `0019`.
--
-- Depende de 0019 (trigger de revisor administrador).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

create or replace function private.solicitudes_validar_revisor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.revisado_por is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.revisado_por is not distinct from old.revisado_por then
    return new;
  end if;

  if new.revisado_por = new.empleado_id then
    raise exception 'Un especialista no puede revisar su propia solicitud'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.perfiles p
    where p.id = new.revisado_por
      and p.empresa_id = new.empresa_id
      and p.rol = 'admin'::public.rol_usuario
      and p.activo
  ) then
    raise exception 'El revisor debe ser administrador activo de la misma empresa'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.solicitudes_validar_revisor() is
  'Exige que revisado_por sea un admin activo de la misma empresa y distinto del especialista, incluso para escrituras con service_role.';
