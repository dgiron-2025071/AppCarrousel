-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-02 / Archivo 25: registro propio con código de empresa
-- Fecha: 2026-11-13
--
-- Crea:
--   1. public.estado_registro        — pendiente / aprobado / rechazado.
--   2. public.registros_pendientes   — solicitud de alta sin perfil todavía.
--   3. public.solicitar_registro()   — el usuario autenticado pide el alta.
--   4. public.aprobar_registro()     — el admin asigna centro y puesto.
--   5. public.rechazar_registro()    — el admin rechaza con motivo.
--   6. RLS y grants                  — el solicitante ve lo suyo; el admin de
--      la empresa ve y resuelve las solicitudes.
--
-- Modelo:
--   `public.perfiles` exige empresa, centro y rol. Un usuario recién registrado
--   no los tiene: por eso el alta vive en `registros_pendientes` hasta que un
--   admin de la empresa le asigna centro y (opcionalmente) puesto. La RPC fija
--   siempre el rol `empleado`; no acepta un rol del cliente, de modo que nadie
--   puede autoelevarse. El perfil se materializa por el trigger de Auth al
--   escribir los claims con service_role.
--
-- Depende de 0004/0022 (perfiles y sync), 0014 (es_admin), 0023 (puestos) y
-- 0002 (empresas, centros_costo).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Estado del registro
-- -----------------------------------------------------------------------------
create type public.estado_registro as enum ('pendiente', 'aprobado', 'rechazado');

comment on type public.estado_registro is
  'Ciclo de vida de una solicitud de alta por código de empresa.';

-- -----------------------------------------------------------------------------
-- 2. Registros pendientes
-- -----------------------------------------------------------------------------
create table public.registros_pendientes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete restrict,
  usuario_id      uuid not null references auth.users (id) on delete cascade,
  email           extensions.citext not null,
  nombre_completo extensions.citext not null,
  estado          public.estado_registro not null default 'pendiente',
  centro_costo_id uuid,
  puesto_id       uuid,
  motivo_rechazo  text,
  revisado_por    uuid,
  revisado_en     timestamptz,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users (id) on delete set null,

  constraint registros_centro_fk
    foreign key (empresa_id, centro_costo_id)
    references public.centros_costo (empresa_id, id)
    on delete restrict,
  constraint registros_puesto_fk
    foreign key (empresa_id, puesto_id)
    references public.puestos (empresa_id, id)
    on delete restrict,
  constraint registros_revisor_fk
    foreign key (empresa_id, revisado_por)
    references public.perfiles (empresa_id, id)
    on delete restrict,
  constraint registros_nombre_valido
    check (length(btrim(nombre_completo::text)) between 1 and 160),
  constraint registros_motivo_valido
    check (motivo_rechazo is null
           or length(btrim(motivo_rechazo)) between 5 and 1000),
  constraint registros_estado_coherente
    check (
      (
        estado = 'pendiente'
        and centro_costo_id is null
        and puesto_id is null
        and motivo_rechazo is null
        and revisado_por is null
        and revisado_en is null
      )
      or (
        estado = 'aprobado'
        and centro_costo_id is not null
        and motivo_rechazo is null
        and revisado_por is not null
        and revisado_en is not null
      )
      or (
        estado = 'rechazado'
        and centro_costo_id is null
        and puesto_id is null
        and motivo_rechazo is not null
        and revisado_por is not null
        and revisado_en is not null
      )
    )
);

comment on table public.registros_pendientes is
  'Solicitudes de alta por código de empresa. El perfil no existe hasta que un admin la aprueba.';
comment on column public.registros_pendientes.usuario_id is
  'Cuenta de Auth que pidió el alta. No se puede elegir desde el cliente.';
comment on column public.registros_pendientes.revisado_por is
  'Admin que aprobó o rechazó el alta. Se conserva como evidencia (ON DELETE RESTRICT).';

create index registros_empresa_estado_idx
  on public.registros_pendientes (empresa_id, estado, creado_en desc);

create index registros_usuario_idx
  on public.registros_pendientes (usuario_id);

-- Un usuario solo puede tener una solicitud viva a la vez. Un rechazo libera
-- el alta para que pueda corregir y volver a solicitar.
create unique index registros_un_pendiente_por_usuario
  on public.registros_pendientes (usuario_id)
  where estado = 'pendiente';

create trigger registros_pendientes_auditoria
before update on public.registros_pendientes
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3. Solicitar el alta
-- -----------------------------------------------------------------------------
create or replace function public.solicitar_registro(
  p_codigo_empresa text,
  p_nombre_completo text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid := auth.uid();
  v_empresa_id uuid;
  v_email      text;
  v_nombre     text;
  v_id         uuid;
begin
  if v_usuario_id is null then
    raise exception 'Se requiere una sesión autenticada'
      using errcode = '42501';
  end if;

  v_nombre := btrim(coalesce(p_nombre_completo, ''));
  if length(v_nombre) not between 1 and 160 then
    raise exception 'El nombre completo debe tener entre 1 y 160 caracteres'
      using errcode = '23514';
  end if;

  if exists (select 1 from public.perfiles p where p.id = v_usuario_id) then
    raise exception 'Ya tienes un perfil aprovisionado en Carrousel'
      using errcode = '23514';
  end if;

  select e.id
    into v_empresa_id
  from public.empresas e
  where e.codigo = btrim(coalesce(p_codigo_empresa, ''))::extensions.citext
    and e.activa;

  if not found then
    raise exception 'El código de empresa no existe o la empresa está suspendida'
      using errcode = '23503';
  end if;

  if exists (
    select 1
    from public.registros_pendientes r
    where r.usuario_id = v_usuario_id
      and r.estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de alta pendiente'
      using errcode = '23505';
  end if;

  select coalesce(
           u.email,
           nullif(auth.jwt() ->> 'email', '')
         )
    into v_email
  from auth.users u
  where u.id = v_usuario_id;

  if v_email is null then
    raise exception 'La cuenta no tiene un correo asociado'
      using errcode = '23514';
  end if;

  insert into public.registros_pendientes (
    empresa_id, usuario_id, email, nombre_completo
  )
  values (
    v_empresa_id, v_usuario_id, v_email::extensions.citext, v_nombre
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.solicitar_registro(text, text) is
  'Registra una solicitud de alta para la empresa del código indicado. El rol final siempre será empleado.';

revoke all on function public.solicitar_registro(text, text) from public;
grant execute on function public.solicitar_registro(text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Aprobar el alta
-- -----------------------------------------------------------------------------
create or replace function public.aprobar_registro(
  p_registro_id uuid,
  p_centro_costo_id uuid,
  p_puesto_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registro public.registros_pendientes%rowtype;
  v_empresa_id uuid := private.current_empresa_id();
  v_usuario_id uuid;
begin
  if auth.uid() is null or not private.es_admin() then
    raise exception 'Solo un administrador activo puede aprobar registros'
      using errcode = '42501';
  end if;

  select r.*
    into v_registro
  from public.registros_pendientes r
  where r.id = p_registro_id
    and r.empresa_id = v_empresa_id
  for update;

  if not found then
    raise exception 'El registro no existe en tu empresa'
      using errcode = '23503';
  end if;

  if v_registro.estado <> 'pendiente' then
    raise exception 'El registro ya fue resuelto'
      using errcode = '23514';
  end if;

  if exists (select 1 from public.perfiles p where p.id = v_registro.usuario_id) then
    raise exception 'La cuenta ya tiene un perfil aprovisionado'
      using errcode = '23505';
  end if;

  if p_centro_costo_id is null or not private.centro_en_alcance(p_centro_costo_id) then
    raise exception 'El centro de costo debe estar dentro de tu alcance'
      using errcode = '42501';
  end if;

  if p_puesto_id is not null and not exists (
    select 1
    from public.puestos pu
    where pu.id = p_puesto_id
      and pu.empresa_id = v_empresa_id
      and pu.activo
  ) then
    raise exception 'El puesto no existe, está inactivo o es de otra empresa'
      using errcode = '23503';
  end if;

  -- El rol se fija aquí, nunca llega del cliente. El trigger de Auth crea el
  -- perfil al escribir los claims.
  update auth.users u
     set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb)
       || jsonb_strip_nulls(
            jsonb_build_object(
              'empresa_id', v_empresa_id,
              'centro_costo_id', p_centro_costo_id,
              'puesto_id', p_puesto_id,
              'rol', 'empleado'
            )
          )
   where u.id = v_registro.usuario_id;

  if not found then
    raise exception 'La cuenta del solicitante ya no existe'
      using errcode = '23503';
  end if;

  update public.registros_pendientes r
     set estado = 'aprobado',
         centro_costo_id = p_centro_costo_id,
         puesto_id = p_puesto_id,
         revisado_por = auth.uid(),
         revisado_en = now(),
         actualizado_por = auth.uid()
   where r.id = v_registro.id;

  v_usuario_id := v_registro.usuario_id;
  return v_usuario_id;
end;
$$;

comment on function public.aprobar_registro(uuid, uuid, uuid) is
  'Aprueba un alta: asigna centro y puesto dentro del alcance del admin y escribe los claims con rol empleado.';

revoke all on function public.aprobar_registro(uuid, uuid, uuid) from public;
grant execute on function public.aprobar_registro(uuid, uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Rechazar el alta
-- -----------------------------------------------------------------------------
create or replace function public.rechazar_registro(
  p_registro_id uuid,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registro public.registros_pendientes%rowtype;
  v_empresa_id uuid := private.current_empresa_id();
  v_motivo     text;
begin
  if auth.uid() is null or not private.es_admin() then
    raise exception 'Solo un administrador activo puede rechazar registros'
      using errcode = '42501';
  end if;

  v_motivo := btrim(coalesce(p_motivo, ''));
  if length(v_motivo) not between 5 and 1000 then
    raise exception 'El motivo debe tener entre 5 y 1000 caracteres'
      using errcode = '23514';
  end if;

  select r.*
    into v_registro
  from public.registros_pendientes r
  where r.id = p_registro_id
    and r.empresa_id = v_empresa_id
  for update;

  if not found then
    raise exception 'El registro no existe en tu empresa'
      using errcode = '23503';
  end if;

  if v_registro.estado <> 'pendiente' then
    raise exception 'El registro ya fue resuelto'
      using errcode = '23514';
  end if;

  update public.registros_pendientes r
     set estado = 'rechazado',
         motivo_rechazo = v_motivo,
         revisado_por = auth.uid(),
         revisado_en = now(),
         actualizado_por = auth.uid()
   where r.id = v_registro.id;
end;
$$;

comment on function public.rechazar_registro(uuid, text) is
  'Rechaza un alta con un motivo obligatorio. El solicitante puede volver a intentarlo.';

revoke all on function public.rechazar_registro(uuid, text) from public;
grant execute on function public.rechazar_registro(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. RLS: registros pendientes
-- -----------------------------------------------------------------------------
alter table public.registros_pendientes enable row level security;

create policy registros_select_propio_o_admin
  on public.registros_pendientes
  for select
  to authenticated
  using (
    usuario_id = (select auth.uid())
    or (
      empresa_id = (select private.current_empresa_id())
      and (select private.es_admin())
    )
  );

comment on policy registros_select_propio_o_admin on public.registros_pendientes is
  'El solicitante ve su registro; el admin ve los de su empresa. La escritura solo ocurre por RPC.';

-- Sin políticas de INSERT/UPDATE/DELETE: el alta y su resolución pasan por las
-- RPC anteriores. Tampoco se otorgan privilegios de escritura de tabla.

-- -----------------------------------------------------------------------------
-- 7. Grants explícitos
-- -----------------------------------------------------------------------------
revoke all on table public.registros_pendientes from anon, authenticated;

grant select on table public.registros_pendientes to authenticated;
