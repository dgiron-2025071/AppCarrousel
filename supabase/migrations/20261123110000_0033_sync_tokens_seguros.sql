-- =============================================================================
-- MT-03 / Archivo 33: tokens internos de sincronizacion
-- =============================================================================
-- Las marcas `carrousel.ajuste_jornada` y `carrousel.parques_centros_sync` eran
-- GUCs libres: cualquier cliente podia fijarlos con `set_config(..., true)` y
-- saltarse la geocerca al cerrar una jornada o borrar el CECO principal de un
-- parque. Aqui se sustituyen por tokens imprevisibles guardados en una tabla
-- de `private`. Solo las funciones SECURITY DEFINER pueden marcarlos y
-- validarlos; el cliente no tiene EXECUTE sobre los helpers ni permisos sobre
-- la tabla.
-- =============================================================================

create table if not exists private.sync_tokens (
  nombre text primary key,
  token  uuid not null default gen_random_uuid()
);

insert into private.sync_tokens (nombre) values
  ('ajuste_jornada'),
  ('parques_centros_sync')
on conflict (nombre) do nothing;

revoke all on table private.sync_tokens from public, anon, authenticated;

comment on table private.sync_tokens is
  'Tokens de un solo uso transaccional para marcas internas. Nunca expuestos al cliente.';

-- -----------------------------------------------------------------------------
-- 1. Helpers de marca: calculan el GUC a partir de un nombre permitido y leen
--    el token real de la tabla. Revocados a PUBLIC: solo se llaman desde
--    funciones SECURITY DEFINER.
-- -----------------------------------------------------------------------------
create or replace function private.sync_guc(p_nombre text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_nombre
    when 'ajuste_jornada' then 'carrousel.sync_ajuste_jornada'
    when 'parques_centros_sync' then 'carrousel.sync_parques_centros'
    else null
  end;
$$;

create or replace function private.sync_marcar(p_nombre text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guc   text := private.sync_guc(p_nombre);
  v_token uuid;
begin
  if v_guc is null then
    raise exception 'Marca de sincronizacion desconocida'
      using errcode = '22023';
  end if;

  select t.token into v_token
  from private.sync_tokens t
  where t.nombre = p_nombre;

  if v_token is null then
    raise exception 'No hay token de sincronizacion para %', p_nombre
      using errcode = '22023';
  end if;

  perform set_config(v_guc, v_token::text, true);
end;
$$;

create or replace function private.sync_desmarcar(p_nombre text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guc text := private.sync_guc(p_nombre);
begin
  if v_guc is null then
    raise exception 'Marca de sincronizacion desconocida'
      using errcode = '22023';
  end if;

  perform set_config(v_guc, '', true);
end;
$$;

create or replace function private.sync_token_valido(p_nombre text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_guc   text := private.sync_guc(p_nombre);
  v_token text;
begin
  if v_guc is null then
    return false;
  end if;

  select t.token::text into v_token
  from private.sync_tokens t
  where t.nombre = p_nombre;

  return v_token is not null
     and coalesce(current_setting(v_guc, true), '') = v_token;
end;
$$;

comment on function private.sync_marcar(text) is
  'Fija el token real de la marca en la transaccion actual. Solo para uso interno.';

comment on function private.sync_desmarcar(text) is
  'Limpia la marca al terminar la operacion interna.';

comment on function private.sync_token_valido(text) is
  'Compara la marca de la transaccion con el token almacenado. Un GUC inventado no basta.';

revoke all on function private.sync_guc(text) from public, anon, authenticated;
revoke all on function private.sync_marcar(text) from public, anon, authenticated;
revoke all on function private.sync_desmarcar(text) from public, anon, authenticated;
revoke all on function private.sync_token_valido(text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Cierre de jornada: el ajuste administrativo ya no se habilita con un GUC
--    cualquiera, sino con el token que pone `public.ajustar_jornada()`.
-- -----------------------------------------------------------------------------
create or replace function private.jornadas_cerrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dentro_actual   boolean;
  v_dentro_entrada  boolean;
begin
  if private.sync_token_valido('ajuste_jornada') then
    return new;
  end if;

  if auth.uid() is null then
    return new;
  end if;

  new.salida_en := coalesce(new.salida_en, clock_timestamp());

  v_dentro_actual := private.en_geocerca_parque(
    new.parque_id, new.salida_lat, new.salida_lon,
    new.salida_precision_metros, false
  );

  v_dentro_entrada := private.en_geocerca_snapshot(
    new.salida_lat, new.salida_lon, new.salida_precision_metros,
    new.entrada_parque_lat, new.entrada_parque_lon,
    new.entrada_parque_radio_metros
  );

  new.salida_dentro_geocerca :=
    coalesce(v_dentro_actual, false) or coalesce(v_dentro_entrada, false);

  if new.salida_dentro_geocerca is not true then
    raise exception 'La salida está fuera de la geocerca del parque'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.ajustar_jornada(
  p_jornada_id uuid,
  p_entrada_en timestamptz,
  p_salida_en timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_jornada   public.jornadas%rowtype;
  v_motivo    text;
  v_ajuste_id uuid;
  v_empresa   uuid := private.current_empresa_id();
begin
  if auth.uid() is null or not private.es_admin() then
    raise exception 'Solo un administrador activo puede ajustar jornadas'
      using errcode = '42501';
  end if;

  v_motivo := btrim(coalesce(p_motivo, ''));
  if length(v_motivo) not between 10 and 2000 then
    raise exception 'El motivo del ajuste debe tener entre 10 y 2000 caracteres'
      using errcode = '23514';
  end if;

  if p_entrada_en is null or p_salida_en is null or p_salida_en <= p_entrada_en then
    raise exception 'El rango del ajuste debe tener entrada y salida, con salida posterior'
      using errcode = '23514';
  end if;

  select j.*
    into v_jornada
  from public.jornadas j
  where j.id = p_jornada_id
    and j.empresa_id = v_empresa
  for update;

  if not found then
    raise exception 'La jornada no existe en tu empresa'
      using errcode = '23503';
  end if;

  if v_jornada.salida_en is null then
    raise exception 'La jornada debe estar cerrada para poder ajustarse'
      using errcode = '23514';
  end if;

  if not private.perfil_en_alcance(v_jornada.empleado_id) then
    raise exception 'La jornada está fuera de tu alcance'
      using errcode = '42501';
  end if;

  insert into public.jornadas_ajustes (
    empresa_id, jornada_id, empleado_id, ajustado_por, motivo,
    entrada_en_anterior, salida_en_anterior,
    entrada_en_nueva, salida_en_nueva
  )
  values (
    v_jornada.empresa_id, v_jornada.id, v_jornada.empleado_id, auth.uid(),
    v_motivo,
    v_jornada.entrada_en, v_jornada.salida_en,
    p_entrada_en, p_salida_en
  )
  returning id into v_ajuste_id;

  perform private.sync_marcar('ajuste_jornada');

  update public.jornadas j
     set entrada_en = p_entrada_en,
         salida_en = p_salida_en,
         actualizado_por = auth.uid()
   where j.id = v_jornada.id;

  perform private.sync_desmarcar('ajuste_jornada');

  return v_ajuste_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. CECO principal: la sincronizacion de parques usa el token real y ya no
--    puede imitarse con `carrousel.parques_centros_sync = 'on'`.
-- -----------------------------------------------------------------------------
create or replace function private.parques_centros_proteger_principal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.sync_token_valido('parques_centros_sync') then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    if old.principal then
      raise exception 'El CECO principal se gestiona desde el centro del parque'
        using errcode = '23514';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.principal
       and (
         not new.principal
         or new.empresa_id is distinct from old.empresa_id
         or new.parque_id is distinct from old.parque_id
         or new.centro_costo_id is distinct from old.centro_costo_id
       ) then
      raise exception 'El CECO principal se gestiona desde el centro del parque'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if new.principal and new.centro_costo_id is distinct from (
    select p.centro_costo_id
    from public.parques p
    where p.id = new.parque_id
      and p.empresa_id = new.empresa_id
  ) then
    raise exception 'El CECO principal debe coincidir con el centro del parque'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function private.parques_centros_sync_principal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.sync_marcar('parques_centros_sync');

  -- Se conserva la fila anterior como CECO adicional inactivo para no romper
  -- solicitudes históricas que la referencian.
  update public.parques_centros pc
     set principal = false,
         activo = false
   where pc.empresa_id = new.empresa_id
     and pc.parque_id = new.id
     and pc.principal
     and pc.centro_costo_id is distinct from new.centro_costo_id;

  insert into public.parques_centros (
    empresa_id, parque_id, centro_costo_id, principal, activo
  )
  values (new.empresa_id, new.id, new.centro_costo_id, true, true)
  on conflict (empresa_id, parque_id, centro_costo_id) do update
    set principal = true,
        activo = true;

  perform private.sync_desmarcar('parques_centros_sync');

  return null;
end;
$$;
