-- =============================================================================
-- MT-02 / Archivo 32: incidencias al cerrar por coordenadas e índices de soporte
-- =============================================================================
-- La migración 0027 disparaba el recálculo solo con `update of` una lista de
-- columnas. El cierre normal del cliente envía unicamente `salida_lat` y
-- `salida_lon`: el trigger BEFORE sella `salida_en`, pero como esa columna no
-- estaba en el SET, el trigger AFTER no se disparaba y la jornada se cerraba
-- sin incidencias. Aquí el AFTER observa toda actualización y la funcion decide
-- si hubo un cambio relevante (incluidas las coordenadas).
--
-- Tambien se indexan las consultas por jornada y la FK compuesta de
-- incidencias, y se acota la limpieza del jefe al empresa anterior para usar
-- `centros_costo_empresa_jefe_idx`.
-- =============================================================================

create or replace function private.jornadas_incidencias()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.salida_en is null then
    delete from public.incidencias_jornada i where i.jornada_id = new.id;
    return new;
  end if;

  if tg_op = 'INSERT' then
    perform private.jornadas_calcular_incidencias(new.id);
    return new;
  end if;

  if new.salida_en is distinct from old.salida_en
     or new.entrada_en is distinct from old.entrada_en
     or new.parque_id is distinct from old.parque_id
     or new.entrada_lat is distinct from old.entrada_lat
     or new.entrada_lon is distinct from old.entrada_lon
     or new.salida_lat is distinct from old.salida_lat
     or new.salida_lon is distinct from old.salida_lon
     or new.entrada_precision_metros is distinct from old.entrada_precision_metros
     or new.salida_precision_metros is distinct from old.salida_precision_metros then
    perform private.jornadas_calcular_incidencias(new.id);
  end if;

  return new;
end;
$$;

comment on function private.jornadas_incidencias() is
  'Recalcula las incidencias al insertar, cerrar o corregir una jornada. Observa toda actualizacion porque el cierre puede sellar salida_en en un trigger BEFORE.';

revoke all on function private.jornadas_incidencias() from public;

drop trigger if exists jornadas_incidencias on public.jornadas;
create trigger jornadas_incidencias
after insert or update on public.jornadas
for each row execute function private.jornadas_incidencias();

-- El recalculo borra y vuelve a insertar por jornada; la FK (empresa_id,
-- jornada_id) necesita su propio indice para validar cambios en jornadas.
create index if not exists incidencias_jornada_idx
  on public.incidencias_jornada (jornada_id, creado_en desc);

create index if not exists incidencias_empresa_jornada_idx
  on public.incidencias_jornada (empresa_id, jornada_id);

-- La designacion anterior vive en la empresa anterior del perfil. Acotar por
-- empresa permite usar centros_costo_empresa_jefe_idx en lugar de un scan.
create or replace function private.limpiar_jefe_de_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.activo
     and new.rol = 'admin'::public.rol_usuario
     and new.empresa_id = old.empresa_id then
    return new;
  end if;

  update public.centros_costo c
     set jefe_id = null
   where c.jefe_id = new.id
     and c.empresa_id = old.empresa_id;

  return new;
end;
$$;

comment on function private.limpiar_jefe_de_perfil() is
  'Limpia centros_costo.jefe_id cuando el perfil deja de ser admin activo de su empresa. Mantiene la jerarquia vigente sin bloquear la sincronizacion de claims.';

revoke all on function private.limpiar_jefe_de_perfil() from public;
