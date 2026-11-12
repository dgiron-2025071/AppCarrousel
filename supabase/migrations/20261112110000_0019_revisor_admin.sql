-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 19: la revisión solo la firma un administrador
-- Fecha: 2026-11-12
--
-- Problema:
--   Las políticas RLS impiden que un empleado apruebe o rechace solicitudes,
--   pero `service_role` las ignora. Una corrección manual podía dejar una
--   solicitud `aprobada` firmada por un perfil `empleado`, o incluso por el
--   propio especialista, sin que ninguna restricción lo detectara. El revisor
--   dejaba de ser evidencia confiable.
--
-- Decisión:
--   Un trigger AFTER INSERT/UPDATE valida, una vez aplicadas las FK y los
--   CHECK, que `revisado_por`:
--     - pertenezca a la misma empresa de la solicitud, y
--     - tenga rol `admin` en `public.perfiles`, y
--     - no sea el propio especialista.
--   Solo se valida al insertar o cuando cambia el revisor, para no bloquear
--   correcciones posteriores sobre una solicitud ya revisada.
--
--   Se usa AFTER para que las violaciones de FK (por ejemplo, un revisor de
--   otra empresa) conserven su código `23503` y sigan siendo identificables.
--
-- Depende de 0006 (trigger de revisión), 0016 (FK compuesta del revisor) y
-- 0018 (coherencia de la revisión).
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
  ) then
    raise exception 'El revisor debe ser administrador de la misma empresa'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.solicitudes_validar_revisor() is
  'Exige que revisado_por sea un admin de la misma empresa y distinto del especialista, incluso para escrituras con service_role.';

revoke all on function private.solicitudes_validar_revisor() from public;

create trigger solicitudes_validar_revisor
after insert or update of revisado_por, estado
on public.solicitudes_horas_extras
for each row execute function private.solicitudes_validar_revisor();
