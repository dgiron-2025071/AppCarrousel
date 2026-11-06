-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 05: jornadas y geocerca de marcaje
-- Fecha: 2026-11-06
--
-- Crea:
--   1. private.distancia_metros()       — distancia haversine reutilizable.
--   2. private.en_geocerca()            — valida un punto contra un parque.
--   3. private.centro_en_empresa()      — valida un centro del tenant.
--   4. private.perfil_en_alcance()      — perfiles dentro del subárbol del admin.
--   5. public.jornadas                  — entrada/salida con coordenadas GPS.
--   6. RLS y grants                     — el empleado marca; el admin supervisa.
--   7. Realtime                         — el dashboard se actualiza en vivo.
--
-- Depende de 0002 (centros_costo, centro_en_alcance), 0003 (parques) y
-- 0004 (perfiles).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Distancia y geocerca
-- -----------------------------------------------------------------------------
create or replace function private.distancia_metros(
  p_lat1 double precision,
  p_lon1 double precision,
  p_lat2 double precision,
  p_lon2 double precision
)
returns double precision
language sql
immutable
security invoker
set search_path = ''
as $$
  select 6371000 * 2 * asin(
    least(
      1.0,
      sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1))
          * cos(radians(p_lat2))
          * power(sin(radians(p_lon2 - p_lon1) / 2), 2)
      )
    )
  );
$$;

comment on function private.distancia_metros(double precision, double precision, double precision, double precision) is
  'Distancia haversine en metros entre dos coordenadas.';

-- La precisión del GPS del dispositivo se suma al radio del parque, con un
-- máximo de 100 m, para no rechazar marcajes válidos por imprecisión normal.
create or replace function private.en_geocerca(
  p_parque_id uuid,
  p_lat double precision,
  p_lon double precision,
  p_precision_metros double precision default 0
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select private.distancia_metros(
               p_lat, p_lon, pa.latitud, pa.longitud
             ) <= pa.radio_metros + least(coalesce(p_precision_metros, 0), 100)
      from public.parques pa
      where pa.id = p_parque_id
        and pa.empresa_id = private.current_empresa_id()
        and pa.activo
    ),
    false
  );
$$;

comment on function private.en_geocerca(uuid, double precision, double precision, double precision) is
  'TRUE si el punto cae dentro del parque activo de la empresa del JWT, tolerando la precisión GPS. Fail-closed.';

create or replace function private.centro_en_empresa(p_centro_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from public.centros_costo c
      where c.id = p_centro_id
        and c.empresa_id = private.current_empresa_id()
    ),
    false
  );
$$;

comment on function private.centro_en_empresa(uuid) is
  'TRUE si el centro pertenece a la empresa del JWT. Fail-closed.';

create or replace function private.perfil_en_alcance(p_usuario_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from public.perfiles p
      where p.id = p_usuario_id
        and p.empresa_id = private.current_empresa_id()
        and private.es_admin()
        and private.centro_en_alcance(p.centro_costo_id)
    ),
    false
  );
$$;

comment on function private.perfil_en_alcance(uuid) is
  'TRUE si el perfil está en el subárbol del admin del JWT. Fail-closed.';

revoke all on function private.distancia_metros(double precision, double precision, double precision, double precision) from public;
revoke all on function private.en_geocerca(uuid, double precision, double precision, double precision) from public;
revoke all on function private.centro_en_empresa(uuid) from public;
revoke all on function private.perfil_en_alcance(uuid) from public;

grant execute on function private.distancia_metros(double precision, double precision, double precision, double precision)
  to authenticated, service_role;
grant execute on function private.en_geocerca(uuid, double precision, double precision, double precision)
  to authenticated, service_role;
grant execute on function private.centro_en_empresa(uuid)
  to authenticated, service_role;
grant execute on function private.perfil_en_alcance(uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Jornadas
-- -----------------------------------------------------------------------------
-- La FK compuesta exige un unique (empresa_id, id) en parques.
alter table public.parques
  add constraint parques_empresa_id_key unique (empresa_id, id);

create table public.jornadas (
  id                        uuid primary key default gen_random_uuid(),
  empresa_id                uuid not null default private.current_empresa_id()
                              references public.empresas (id) on delete restrict,
  empleado_id               uuid not null default auth.uid()
                              references public.perfiles (id) on delete cascade,
  parque_id                 uuid not null,
  entrada_en                timestamptz not null default clock_timestamp(),
  salida_en                 timestamptz,
  entrada_lat               double precision not null,
  entrada_lon               double precision not null,
  entrada_precision_metros  double precision not null default 0,
  entrada_dentro_geocerca   boolean not null default false,
  salida_lat                double precision,
  salida_lon                double precision,
  salida_precision_metros   double precision,
  salida_dentro_geocerca    boolean,
  creado_en                 timestamptz not null default now(),
  actualizado_en            timestamptz not null default now(),
  actualizado_por           uuid references auth.users (id) on delete set null,

  constraint jornadas_parque_fk
    foreign key (empresa_id, parque_id)
    references public.parques (empresa_id, id)
    on delete restrict,
  constraint jornadas_entrada_lat_valida
    check (entrada_lat between -90 and 90),
  constraint jornadas_entrada_lon_valida
    check (entrada_lon between -180 and 180),
  constraint jornadas_salida_lat_valida
    check (salida_lat is null or salida_lat between -90 and 90),
  constraint jornadas_salida_lon_valida
    check (salida_lon is null or salida_lon between -180 and 180),
  constraint jornadas_rango_valido
    check (salida_en is null or salida_en > entrada_en),
  constraint jornadas_duracion_maxima
    check (salida_en is null or salida_en - entrada_en <= interval '24 hours'),
  constraint jornadas_salida_completa
    check (
      salida_en is null
      or (
        salida_lat is not null
        and salida_lon is not null
        and salida_dentro_geocerca is not null
      )
    )
);

comment on table public.jornadas is
  'Jornadas de trabajo del empleado. La entrada abre la jornada y la salida la cierra; ambas se validan contra la geocerca del parque.';
comment on column public.jornadas.empresa_id is
  'Empresa tomada del JWT. El cliente no puede elegirla ni escribirla.';
comment on column public.jornadas.empleado_id is
  'Perfil del empleado. Por defecto auth.uid(); el cliente no puede elegir a otra persona.';
comment on column public.jornadas.entrada_dentro_geocerca is
  'Resultado de la validación GPS al abrir la jornada. Lo escribe el trigger/backend, no el cliente.';
comment on column public.jornadas.salida_dentro_geocerca is
  'Resultado de la validación GPS al cerrar la jornada. Lo escribe el trigger/backend, no el cliente.';

create index jornadas_empresa_empleado_idx
  on public.jornadas (empresa_id, empleado_id, entrada_en desc);

create index jornadas_empresa_parque_idx
  on public.jornadas (empresa_id, parque_id, entrada_en desc);

-- Un empleado no puede tener dos jornadas abiertas a la vez.
create unique index jornadas_una_abierta_por_empleado
  on public.jornadas (empleado_id)
  where salida_en is null;

create trigger jornadas_auditoria
before update on public.jornadas
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3. Validación de entrada y salida
-- -----------------------------------------------------------------------------
-- service_role (auth.uid() NULL) puede sembrar o corregir datos históricos.
-- Los clientes autenticados siempre pasan por la geocerca y por el trigger.
create or replace function private.jornadas_validar_entrada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  new.entrada_dentro_geocerca := private.en_geocerca(
    new.parque_id, new.entrada_lat, new.entrada_lon, new.entrada_precision_metros
  );

  if new.entrada_dentro_geocerca is not true then
    raise exception 'La entrada está fuera de la geocerca del parque'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.jornadas_validar_entrada() is
  'Valida la geocerca al abrir una jornada. service_role puede sembrar datos históricos.';

create or replace function private.jornadas_cerrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  new.salida_en := coalesce(new.salida_en, clock_timestamp());
  new.salida_dentro_geocerca := private.en_geocerca(
    new.parque_id, new.salida_lat, new.salida_lon, new.salida_precision_metros
  );

  if new.salida_dentro_geocerca is not true then
    raise exception 'La salida está fuera de la geocerca del parque'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.jornadas_cerrar() is
  'Cierra la jornada, fija salida_en y valida la geocerca de salida.';

revoke all on function private.jornadas_validar_entrada() from public;
revoke all on function private.jornadas_cerrar() from public;

create trigger jornadas_validar_entrada
before insert on public.jornadas
for each row execute function private.jornadas_validar_entrada();

create trigger jornadas_cerrar
before update on public.jornadas
for each row execute function private.jornadas_cerrar();

-- -----------------------------------------------------------------------------
-- 4. RLS: jornadas
-- -----------------------------------------------------------------------------
alter table public.jornadas enable row level security;

create policy jornadas_select_propia_o_equipo
  on public.jornadas
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      empleado_id = (select auth.uid())
      or private.perfil_en_alcance(empleado_id)
    )
  );

create policy jornadas_insert_propia
  on public.jornadas
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and empleado_id = (select auth.uid())
    and salida_en is null
    and private.en_geocerca(
      parque_id, entrada_lat, entrada_lon, entrada_precision_metros
    )
  );

create policy jornadas_update_propia
  on public.jornadas
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and empleado_id = (select auth.uid())
    and salida_en is null
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and empleado_id = (select auth.uid())
    and salida_en is not null
    and salida_dentro_geocerca is true
  );

comment on policy jornadas_select_propia_o_equipo on public.jornadas is
  'El empleado ve sus jornadas; el admin ve las de su subárbol.';
comment on policy jornadas_insert_propia on public.jornadas is
  'Solo el propio empleado abre una jornada, con GPS dentro de la geocerca.';
comment on policy jornadas_update_propia on public.jornadas is
  'Solo el propio empleado cierra su jornada abierta, con GPS dentro de la geocerca.';

-- -----------------------------------------------------------------------------
-- 5. Grants explícitos
-- -----------------------------------------------------------------------------
revoke all on table public.jornadas from anon, authenticated;

grant select on table public.jornadas to authenticated;
-- empresa_id y empleado_id toman su valor de los claims (DEFAULT); el cliente
-- no puede escribirlos ni falsificarlos.
grant insert (
  parque_id,
  entrada_lat, entrada_lon, entrada_precision_metros
) on table public.jornadas to authenticated;
grant update (
  salida_lat, salida_lon, salida_precision_metros
) on table public.jornadas to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Realtime
-- -----------------------------------------------------------------------------
alter table public.jornadas replica identity full;

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
      and tablename = 'jornadas'
  ) then
    alter publication supabase_realtime add table public.jornadas;
  end if;
end;
$$;
