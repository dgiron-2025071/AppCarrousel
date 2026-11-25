# Validación de base de datos

Suite que aplica las migraciones de `supabase/migrations` sobre un PostgreSQL
17.9 **portátil** y prueba la jerarquía, la geocerca, las jornadas, las
solicitudes de horas extras, los puestos y el autorizador jerárquico, los
horarios, el registro por código de empresa, los CECO por lugar, las
incidencias y ajustes, los reportes, las políticas RLS, la separación de roles
y Realtime.

No requiere Docker, WSL2 ni permisos de administrador: `embedded-postgres`
descarga un binario de PostgreSQL y lo ejecuta como proceso de usuario.

## Cómo ejecutarla

```bash
pnpm --dir tools/db-validation install
pnpm --dir tools/db-validation test
pnpm --dir tools/importar-ceco test
```

La suite del arnés también ejecuta el SQL generado por
[`tools/importar-ceco`](../importar-ceco/README.md) contra este PostgreSQL real:
valida la creación idempotente de la jerarquía, el renombrado y el aborto
completo cuando falta un padre.

En Windows con una sesión elevada, el arnés inicia el clúster con `pg_ctl` en
lugar de lanzar `postgres.exe` directamente: PostgreSQL rechaza los tokens de
administrador y `embedded-postgres` fallaba sin mensaje al hacerlo.

- `PGPORT` permite cambiar el puerto (por defecto `55434`).
- `--keep` conserva el directorio temporal del clúster para inspeccionarlo.
  Sin esa bandera el directorio se borra al terminar.

La suite crea una base `carrousel_test` nueva en cada ejecución, aplica todas
las migraciones en orden y termina con un resumen `OK/FAIL`. Sale con código
distinto de cero si alguna prueba falla.

## Qué emula de Supabase

`supabase-stub.sql` se ejecuta **antes** de las migraciones y crea lo mínimo
que Supabase proporciona en producción:

| Elemento | Emulación local |
|---|---|
| Roles de API | `anon`, `authenticated`, `service_role` |
| `service_role` | `nologin bypassrls` |
| Schema `auth` | `auth.users` con `raw_app_meta_data` y `raw_user_meta_data` |
| `auth.jwt()` | Lee `request.jwt.claims` |
| `auth.uid()` | Extrae `sub` con validación de UUID |
| Claims | `set_config('request.jwt.claims', ...)` dentro de transacciones |

Las pruebas usan `set local role` y revierten cada transacción, así que no
dejan datos ni privilegios modificados.

## Cobertura

- Estructura: las 12 tablas de negocio, extensión `citext`/`pgcrypto`, RLS en
  todas, al menos una política por tabla y un mínimo de 18 políticas.
- Invariantes estructurales: toda tabla pública tiene RLS, `anon` no tiene
  escritura de tabla ni de columna, toda función `SECURITY DEFINER` fija
  `search_path` vacío y ninguna función de `public`/`private` queda ejecutable
  por `PUBLIC`/`anon`, para que una migración futura no abra un hueco sin que
  las pruebas funcionales lo detecten. Pruebas negativas dentro de una
  transacción revertida confirman que el arnés detecta cada uno de esos
  accesos.
- Índices de RLS y reportes: el arnés comprueba en `pg_indexes` la definición
  de los índices de `perfiles`, `centros_costo`, `parques`, `parques_centros`,
  `jornadas`, `solicitudes_horas_extras`, `registros_pendientes`,
  `incidencias_jornada`, `jornadas_ajustes`, `horarios` y `puestos`, y en
  `pg_constraint` la restricción de exclusión `solicitudes_sin_solape`. También
  extrae de las migraciones todo `CREATE INDEX` y exige que el índice exista en
  la base. Una migración que elimine, renombre o reordene esos índices rompe la
  suite.
- Jerarquía: cálculo de `ruta`, FK cross-tenant, anti-ciclos, códigos únicos
  por empresa y límite de 32 niveles.
- Propagación de `ruta` al subárbol al mover un centro.
- RLS de `empresas`, `centros_costo` y `parques` por tenant y subárbol.
- Geocerca: rango de latitud/longitud y radio entre 1 y 10 000 m.
- Distancia haversine, tolerancia fija de precisión GPS (100 m) al evaluar la
  geocerca y fail-closed sin claims o con parque de otra empresa. Ese valor no
  es el umbral configurable de la empresa
  (`empresas.gps_precision_maxima_metros`, 10–1000 m en la migración `0024`),
  que determina cuándo un marcaje se reporta como impreciso.
- Jornadas: apertura/cierre por el propio empleado, validación de geocerca en
  base de datos, una sola jornada abierta por empleado, inmutabilidad de
  columnas sensibles, RLS por subárbol y conservación del historial.
- Endurecimiento operativo: marcaje limitado a parques del subárbol, cierre de
  una jornada abierta aunque el parque se desactive durante el turno, rechazo
  de precisión GPS negativa y bloqueo de escritura para perfiles inactivos
  (jornadas, solicitudes y administración de centros).
- Revocación de lectura: un admin inactivo solo ve su propio perfil, jornadas y
  solicitudes; pierde de inmediato el acceso al equipo sin esperar a que
  expire el JWT. Un empleado inactivo conserva la lectura de su información.
- Jornadas olvidadas: una jornada abierta de más de 24 h se puede cerrar con el
  tiempo real trabajado, sin quedar atrapada por el índice de jornada abierta.
- Horas extras: creación de solicitudes pendientes, rango y duración válidos,
  justificación mínima, centro de la misma empresa, aprobación/rechazo por el
  admin del subárbol, comentario opcional, firma automática de la revisión y
  prohibición de revisar solicitudes propias, ajenas o ya revisadas.
- Retiro de solicitudes: el especialista cancela únicamente su propia solicitud
  pendiente. Se conserva la fila con `revisado_en` como marca de cierre,
  `revisado_por` queda NULL, el comentario no puede escribirse y el admin ya no
  puede aprobarla ni rechazarla.
- Retención del historial: las FK de empleado en `jornadas` y
  `solicitudes_horas_extras` usan `ON DELETE RESTRICT`. Borrar una cuenta con
  actividad falla y conserva el perfil, las jornadas y las solicitudes; la baja
  de personal se hace desactivando `public.perfiles.activo`.
- Empresas inactivas: `empresas.activa = false` hace que
  `private.current_empresa_id()` devuelva NULL. El tenant deja de exponer
  empresa, centros, parques, jornadas y solicitudes, y sus administradores no
  pueden escribir. Al reactivarla se recupera el acceso. Otra empresa activa no
  se ve afectada.
- Degradación de administradores: `private.es_admin()` exige que el JWT diga
  `admin` y que el perfil materializado siga siendo `admin` activo de la empresa
  activa y del mismo centro. Un admin degradado o movido de subárbol deja de
  aprobar y de ver su antiguo equipo de inmediato, aunque su JWT aún no haya
  expirado; al refrescar la sesión con el centro nuevo recupera el rol.
- Geocerca congelada: al abrir la jornada se guardan latitud, longitud y radio
  del parque. El cierre acepta la geocerca actual o la foto de entrada, así que
  mover o redimensionar el parque durante el turno no atrapa al empleado. Un
  turno nuevo en la ubicación nueva ya no cierra en la anterior y el cliente no
  puede escribir la foto.
- Integridad cross-tenant: las FK de empleado en `jornadas` y
  `solicitudes_horas_extras` y la del revisor incluyen `empresa_id`. No se puede
  referenciar un perfil de otra empresa, borrar al revisor ni mover de empresa a
  un empleado con historial.
- Coherencia y solape de horas extras: pendiente no tiene revisor ni comentario;
  cancelada cierra sin revisor; aprobada y rechazada exigen la firma. Una
  restricción de exclusión GiST impide dos solicitudes vivas del mismo
  especialista con rangos solapados; rechazadas y canceladas liberan el rango y
  los rangos contiguos no cuentan como solape. Un trigger exige que el revisor
  sea un `admin` activo de la misma empresa y distinto del especialista, incluso
  cuando la escritura llega con `service_role`; desactivarlo no invalida las
  revisiones que ya firmó. Cambiar el especialista o la empresa de una solicitud
  vuelve a ejecutar la validación del revisor.
- Realtime: `jornadas` y `solicitudes_horas_extras` en la publicación
  `supabase_realtime` con `replica identity full`.
- Puestos y autorizador: `puestos` aislados por empresa, código único, nombre no
  vacío y solo el admin crea o edita; `perfiles.puesto_id` se materializa desde
  `app_metadata` y el cliente no lo escribe. El jefe de centro debe ser un admin
  activo de la misma empresa; `jefe_de_centro()` resuelve el ancestro más cercano
  y `es_autorizador()` distingue al jefe de su subárbol de otro admin.
- Horarios y GPS: un horario por empleado y día ISO, tolerancias acotadas,
  entrada distinta de salida, lectura por empleado o subárbol; zona horaria IANA
  y umbral de precisión GPS por empresa (10–1000 m); `fecha_local()` y
  `horario_del_dia()` usan esa zona.
- Registro por código: `solicitar_registro` valida el código de empresa, exige
  que el usuario aún no tenga perfil, sincroniza el nombre declarado a
  `user_metadata`, no acumula pendientes y permite reintentar tras un rechazo;
  `aprobar_registro` siempre crea un `empleado`, fija el centro dentro del
  alcance y actualiza los claims; `rechazar_registro` exige un motivo. El cliente
  no inserta en `registros_pendientes`.
- Puesto declarado: `solicitar_registro(text,text,text)` guarda `Especialista`
  (normalizado) o el texto libre que escriba la persona; la RPC de dos
  argumentos sigue declarando `Especialista`. Se valida longitud, la aprobación
  copia el puesto a los claims y el trigger lo materializa en
  `perfiles.puesto`.
- CECO por lugar: `parques_centros` mantiene exactamente un principal por
  parque, sincronizado con `parques.centro_costo_id`; mover el parque desactiva
  el principal anterior y activa el nuevo conservando el historial. La solicitud
  guarda `parque_id` y exige que el CECO esté habilitado en ese lugar y en la
  misma empresa; las solicitudes históricas sin lugar siguen siendo válidas.
- Incidencias y ajustes: al cerrar se calculan `llegada_tarde`,
  `salida_temprana`, `parque_distinto` y `gps_impreciso` con la zona y el horario
  del empleado. Cerrar enviando solo `salida_lat`/`salida_lon` también genera
  incidencias: el trigger AFTER observa toda actualización porque `salida_en` lo
  sella un trigger BEFORE. Hay índices por jornada y para la FK compuesta, y la
  limpieza del jefe acota por empresa. `jornadas_ajustes` es inmutable (sin
  UPDATE ni DELETE) y `ajustar_jornada` exige motivo y rango coherente, rechaza
  jornadas abiertas o de otra empresa, actualiza la jornada y recalcula las
  incidencias.
- Tokens de sincronización: el ajuste de jornada y el CECO principal ya no se
  habilitan con GUCs que el cliente pueda fijar. `private.sync_tokens` guarda un
  token por marca, los helpers `security definer` son los únicos que pueden
  marcarlo y validarlo, y el arnés comprueba que un UUID falso (y los GUCs
  heredados) no saltan la geocerca ni desprenden el principal.
- Reportes: `reporte_horas_extras` y `cumplimiento_jornadas` usan
  `security_invoker = true`; el empleado solo ve lo propio, el admin su subárbol
  y ninguna empresa ve a otra. El cálculo de horas y el cruce con horario e
  incidencias se validan con datos reales.
- Importación de CECO: el CSV se normaliza y se convierte en SQL idempotente; el
  arnés comprueba creación, jerarquía, renombrado, repetición sin duplicados y
  rollback completo cuando falta un padre.
- Perfiles: materialización desde `app_metadata`, alcance inválido, cambio
  administrativo de rol y borrado en cascada. Si una actualización de
  `auth.users` deja los claims incompletos, el perfil existente se desactiva;
  restaurar los claims actualiza el alcance pero no reactiva una baja.
- No autoelevación: `authenticated` no puede escribir `rol`, `empresa_id`,
  `empleado_id`, `centro_costo_id`, `puesto_id`, `ruta`, `actualizado_por` ni
  `auth.users`; además no tiene `UPDATE` de tabla ni permisos de columna para
  `rol`, `empresa_id` o `centro_costo_id` en `perfiles`.
- Fail-closed: sin claims no hay acceso; `anon` no accede a ninguna tabla ni a
  las vistas de reporte. Todas las vistas públicas usan `security_invoker=true`
  para heredar la RLS del consultante, y una vista nueva sin esa opción rompe
  el arnés.
- Auditoría: `actualizado_en` y `actualizado_por`.

Resultado actual: **381 pruebas OK, 0 FAIL**.

## Límites

Esta suite valida el SQL de las migraciones, no el stack completo de Supabase:

- Los JWT son emulados con `request.jwt.claims`, no firmados por GoTrue.
- No ejecuta PostgREST ni comprueba los grants que Supabase añade por defecto.
- No sustituye a `supabase db reset` contra un proyecto Supabase real.

Antes de desplegar a producción, ejecutar las migraciones en un proyecto
Supabase de staging y repetir las pruebas de autoelevación con usuarios reales.
