-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 21: el revisor se revalida al mover la solicitud
-- Fecha: 2026-11-12
--
-- Problema:
--   El trigger de `0019`/`0020` solo se dispara al insertar o cuando cambia
--   `revisado_por` o `estado`. Una escritura con `service_role` podía cambiar
--   `empleado_id` (o `empresa_id`) de una solicitud ya revisada y dejar al
--   revisor apuntando al propio especialista o a otra empresa, sin que la
--   validación volviera a ejecutarse. La evidencia de auditoría se corrompía
--   sin tocar la firma.
--
-- Decisión:
--   El trigger también se dispara al cambiar `empleado_id` o `empresa_id`, y la
--   validación se omite únicamente cuando no cambió ninguno de los cuatro
--   campos. Así se conserva la firma histórica de un admin que luego fue
--   desactivado, pero cualquier reasignación de la solicitud vuelve a exigir un
--   admin activo de la empresa y distinto del especialista.
--
-- Depende de 0019 (validación del revisor) y 0020 (revisor activo).
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

  if tg_op = 'UPDATE'
     and new.revisado_por is not distinct from old.revisado_por
     and new.estado is not distinct from old.estado
     and new.empleado_id is not distinct from old.empleado_id
     and new.empresa_id is not distinct from old.empresa_id then
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
  'Exige que revisado_por sea un admin activo de la misma empresa y distinto del especialista al insertar o reasignar la solicitud, incluso con service_role.';

drop trigger solicitudes_validar_revisor on public.solicitudes_horas_extras;

create trigger solicitudes_validar_revisor
after insert or update of revisado_por, estado, empleado_id, empresa_id
on public.solicitudes_horas_extras
for each row execute function private.solicitudes_validar_revisor();
