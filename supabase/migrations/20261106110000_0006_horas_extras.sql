-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 06: solicitudes de horas extras y aprobación
-- Fecha: 2026-11-06
--
-- Crea:
--   1. public.estado_solicitud       — pendiente / aprobada / rechazada.
--   2. public.solicitudes_horas_extras — solicitud del especialista.
--   3. Revisión administrativa       — admin aprueba/rechaza con comentario.
--   4. RLS                           — empleado ve lo suyo; admin ve su equipo.
--   5. Realtime                      — empleado y admin reciben los cambios.
--
-- Depende de 0004 (perfiles) y 0005 (perfil_en_alcance, centro_en_empresa).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Estado de la solicitud
-- -----------------------------------------------------------------------------
create type public.estado_solicitud as enum ('pendiente', 'aprobada', 'rechazada');

comment on type public.estado_solicitud is
  'Ciclo de vida de una solicitud de horas extras.';

-- -----------------------------------------------------------------------------
-- 2. Solicitudes
-- -----------------------------------------------------------------------------
create table public.solicitudes_horas_extras (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null default private.current_empresa_id()
                      references public.empresas (id) on delete restrict,
  empleado_id       uuid not null default auth.uid()
                      references public.perfiles (id) on delete cascade,
  centro_costo_id   uuid not null,
  inicio            timestamptz not null,
  fin               timestamptz not null,
  justificacion     text not null,
  estado            public.estado_solicitud not null default 'pendiente',
  comentario_admin  text,
  revisado_por      uuid references public.perfiles (id) on delete set null,
  revisado_en       timestamptz,
  creado_en         timestamptz not null default now(),
  actualizado_en    timestamptz not null default now(),
  actualizado_por   uuid references auth.users (id) on delete set null,

  constraint solicitudes_centro_fk
    foreign key (empresa_id, centro_costo_id)
    references public.centros_costo (empresa_id, id)
    on delete restrict,
  constraint solicitudes_rango_valido
    check (fin > inicio),
  constraint solicitudes_duracion_maxima
    check (fin - inicio <= interval '24 hours'),
  constraint solicitudes_justificacion_valida
    check (length(btrim(justificacion)) between 10 and 2000),
  constraint solicitudes_comentario_valido
    check (comentario_admin is null or length(comentario_admin) <= 2000),
  -- revisado_por puede quedar NULL si se borra el perfil del admin que revisó;
  -- la marca temporal de revisión se conserva como evidencia.
  constraint solicitudes_revision_coherente
    check (
      (
        estado = 'pendiente'
        and revisado_por is null
        and revisado_en is null
      )
      or (
        estado <> 'pendiente'
        and revisado_en is not null
      )
    )
);

comment on table public.solicitudes_horas_extras is
  'Solicitudes de horas extras del especialista. El admin de su centro las aprueba o rechaza con un comentario opcional.';
comment on column public.solicitudes_horas_extras.empresa_id is
  'Empresa tomada del JWT. El cliente no puede elegirla ni escribirla.';
comment on column public.solicitudes_horas_extras.centro_costo_id is
  'Parque/centro de costo al que el especialista fue a apoyar. Debe pertenecer a la misma empresa.';
comment on column public.solicitudes_horas_extras.empleado_id is
  'Perfil del especialista. Por defecto auth.uid(); el cliente no puede elegir a otra persona.';
comment on column public.solicitudes_horas_extras.estado is
  'Pendiente hasta que el admin la aprueba o rechaza. El cliente no escribe esta columna.';
comment on column public.solicitudes_horas_extras.comentario_admin is
  'Comentario opcional del admin al aprobar o rechazar. Visible para el especialista.';

create index solicitudes_empresa_empleado_idx
  on public.solicitudes_horas_extras (empresa_id, empleado_id, creado_en desc);

create index solicitudes_empresa_estado_idx
  on public.solicitudes_horas_extras (empresa_id, estado, creado_en desc);

create index solicitudes_empresa_centro_idx
  on public.solicitudes_horas_extras (empresa_id, centro_costo_id);

create trigger solicitudes_horas_extras_auditoria
before update on public.solicitudes_horas_extras
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3. Revisión administrativa
-- -----------------------------------------------------------------------------
-- El admin no puede reabrir una solicitud ni cambiar el empleado. El trigger
-- fija quién revisó y cuándo, datos que el cliente no puede falsificar.
create or replace function private.solicitudes_set_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.estado is distinct from old.estado then
    if new.estado = 'pendiente' then
      raise exception 'Una solicitud revisada no puede volver a pendiente'
        using errcode = '23514';
    end if;

    new.revisado_por := auth.uid();
    new.revisado_en  := now();
  else
    -- Solo se permite cambiar el comentario de una solicitud ya revisada.
    new.revisado_por := old.revisado_por;
    new.revisado_en  := old.revisado_en;
  end if;

  return new;
end;
$$;

comment on function private.solicitudes_set_revision() is
  'Fija revisado_por/revisado_en desde el JWT y evita reabrir una solicitud.';

revoke all on function private.solicitudes_set_revision() from public;

create trigger solicitudes_set_revision
before update on public.solicitudes_horas_extras
for each row execute function private.solicitudes_set_revision();

-- -----------------------------------------------------------------------------
-- 4. RLS: solicitudes
-- -----------------------------------------------------------------------------
alter table public.solicitudes_horas_extras enable row level security;

create policy solicitudes_select_propia_o_equipo
  on public.solicitudes_horas_extras
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      empleado_id = (select auth.uid())
      or private.perfil_en_alcance(empleado_id)
    )
  );

create policy solicitudes_insert_propia
  on public.solicitudes_horas_extras
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and empleado_id = (select auth.uid())
    and estado = 'pendiente'
    and revisado_por is null
    and revisado_en is null
    and comentario_admin is null
    and private.centro_en_empresa(centro_costo_id)
  );

create policy solicitudes_update_admin
  on public.solicitudes_horas_extras
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and private.es_admin()
    and private.perfil_en_alcance(empleado_id)
    and empleado_id <> (select auth.uid())
    and estado = 'pendiente'
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and private.es_admin()
    and private.perfil_en_alcance(empleado_id)
    and empleado_id <> (select auth.uid())
    and estado in ('aprobada', 'rechazada')
    and revisado_por = (select auth.uid())
    and revisado_en is not null
  );

comment on policy solicitudes_select_propia_o_equipo on public.solicitudes_horas_extras is
  'El especialista ve sus solicitudes; el admin ve las de los perfiles de su subárbol.';
comment on policy solicitudes_insert_propia on public.solicitudes_horas_extras is
  'Solo el propio especialista crea solicitudes pendientes para un centro de su empresa.';
comment on policy solicitudes_update_admin on public.solicitudes_horas_extras is
  'Solo un admin aprueba o rechaza solicitudes pendientes de su subárbol. No puede revisar las propias.';

-- Sin políticas de DELETE: el historial de solicitudes se conserva.

-- -----------------------------------------------------------------------------
-- 5. Grants explícitos
-- -----------------------------------------------------------------------------
revoke all on table public.solicitudes_horas_extras from anon, authenticated;

grant select on table public.solicitudes_horas_extras to authenticated;
-- empresa_id y empleado_id toman su valor de los claims (DEFAULT); el cliente
-- no puede escribirlos ni falsificarlos.
grant insert (
  centro_costo_id, inicio, fin, justificacion
) on table public.solicitudes_horas_extras to authenticated;
grant update (
  estado, comentario_admin
) on table public.solicitudes_horas_extras to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Realtime
-- -----------------------------------------------------------------------------
alter table public.solicitudes_horas_extras replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'solicitudes_horas_extras'
  ) then
    alter publication supabase_realtime add table public.solicitudes_horas_extras;
  end if;
end;
$$;
