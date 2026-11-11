-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 15: foto de la geocerca al abrir la jornada
-- Fecha: 2026-11-11
--
-- Problema:
--   El cierre validaba la salida contra la geocerca *actual* del parque. Si un
--   administrador movía el parque o reducía su radio durante el turno, el
--   empleado quedaba atrapado: no podía cerrar la jornada desde el lugar donde
--   había entrado, aunque su marcaje de entrada había sido válido.
--
-- Decisión:
--   Al abrir la jornada se copian latitud, longitud y radio del parque en la
--   propia fila (`entrada_parque_*`). El cierre acepta el punto si cae dentro de
--   la geocerca actual **o** de la foto tomada al entrar. Así no se castiga al
--   empleado por un cambio administrativo posterior, y el historial conserva
--   contra qué geocerca se validó la entrada. El cliente no puede escribir esas
--   columnas: no están en los grants de INSERT.
--
-- Depende de 0005 (jornadas, en_geocerca_parque) y 0007 (cierre con parque
-- desactivado).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Columnas de la foto y backfill de las jornadas existentes
-- -----------------------------------------------------------------------------
alter table public.jornadas
  add column entrada_parque_lat double precision,
  add column entrada_parque_lon double precision,
  add column entrada_parque_radio_metros integer;

-- Para las jornadas previas no existe una foto histórica: se usa la geocerca
-- vigente del parque en el momento de migrar, que es la mejor evidencia
-- disponible. El FK de jornadas impide que el parque falte.
update public.jornadas j
   set entrada_parque_lat = p.latitud,
       entrada_parque_lon = p.longitud,
       entrada_parque_radio_metros = p.radio_metros
  from public.parques p
 where p.id = j.parque_id;

alter table public.jornadas
  alter column entrada_parque_lat set not null,
  alter column entrada_parque_lon set not null,
  alter column entrada_parque_radio_metros set not null,
  add constraint jornadas_entrada_parque_lat_valida
    check (entrada_parque_lat between -90 and 90),
  add constraint jornadas_entrada_parque_lon_valida
    check (entrada_parque_lon between -180 and 180),
  add constraint jornadas_entrada_parque_radio_valido
    check (entrada_parque_radio_metros between 1 and 10000);

comment on column public.jornadas.entrada_parque_lat is
  'Latitud del parque al abrir la jornada. El cierre la usa como geocerca de respaldo si el parque se movió durante el turno.';
comment on column public.jornadas.entrada_parque_lon is
  'Longitud del parque al abrir la jornada. El cierre la usa como geocerca de respaldo si el parque se movió durante el turno.';
comment on column public.jornadas.entrada_parque_radio_metros is
  'Radio de la geocerca al abrir la jornada. El cierre lo usa como respaldo si el parque se redimensionó durante el turno.';

-- -----------------------------------------------------------------------------
-- 2. Validación contra una geocerca congelada
-- -----------------------------------------------------------------------------
create or replace function private.en_geocerca_snapshot(
  p_lat double precision,
  p_lon double precision,
  p_precision_metros double precision,
  p_parque_lat double precision,
  p_parque_lon double precision,
  p_parque_radio_metros integer
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    private.distancia_metros(p_lat, p_lon, p_parque_lat, p_parque_lon)
      <= p_parque_radio_metros + least(coalesce(p_precision_metros, 0), 100),
    false
  );
$$;

comment on function private.en_geocerca_snapshot(double precision, double precision, double precision, double precision, double precision, integer) is
  'Valida un punto contra una geocerca congelada (lat, lon y radio del parque al entrar). Fail-closed.';

revoke all on function private.en_geocerca_snapshot(double precision, double precision, double precision, double precision, double precision, integer) from public;
grant execute on function private.en_geocerca_snapshot(double precision, double precision, double precision, double precision, double precision, integer)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Entrada: congelar la geocerca del parque
-- -----------------------------------------------------------------------------
create or replace function private.jornadas_validar_entrada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- La foto se toma incluso para cargas de service_role. Si service_role ya
  -- envió una foto explícita (carga histórica), se respeta.
  if new.entrada_parque_lat is null
     or new.entrada_parque_lon is null
     or new.entrada_parque_radio_metros is null then
    select p.latitud, p.longitud, p.radio_metros
      into new.entrada_parque_lat,
           new.entrada_parque_lon,
           new.entrada_parque_radio_metros
    from public.parques p
    where p.id = new.parque_id;

    if new.entrada_parque_lat is null then
      raise exception 'El parque de la jornada no existe'
        using errcode = '23503';
    end if;
  end if;

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
  'Congela la geocerca del parque y valida la entrada. service_role puede sembrar datos históricos y aportar su propia foto.';

-- -----------------------------------------------------------------------------
-- 4. Cierre: aceptar la geocerca actual o la foto de entrada
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
  if auth.uid() is null then
    return new;
  end if;

  new.salida_en := coalesce(new.salida_en, clock_timestamp());

  -- La geocerca actual no exige que el parque siga activo: la desactivación
  -- durante el turno no debe atrapar al empleado.
  v_dentro_actual := private.en_geocerca_parque(
    new.parque_id, new.salida_lat, new.salida_lon,
    new.salida_precision_metros, false
  );

  -- La foto de entrada cubre que el parque se haya movido o redimensionado.
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

comment on function private.jornadas_cerrar() is
  'Cierra la jornada y valida la salida contra la geocerca actual o la foto tomada al entrar. No exige que el parque siga activo.';
