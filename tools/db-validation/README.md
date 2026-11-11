# Validación de base de datos

Suite que aplica las migraciones de `supabase/migrations` sobre un PostgreSQL
17.9 **portátil** y prueba la jerarquía, la geocerca, las jornadas, las
solicitudes de horas extras, las políticas RLS, la separación de roles y
Realtime.

No requiere Docker, WSL2 ni permisos de administrador: `embedded-postgres`
descarga un binario de PostgreSQL y lo ejecuta como proceso de usuario.

## Cómo ejecutarla

```bash
pnpm --dir tools/db-validation install
pnpm --dir tools/db-validation test
```

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

- Estructura: tablas, extensión `citext`/`pgcrypto`, RLS y número de políticas.
- Jerarquía: cálculo de `ruta`, FK cross-tenant, anti-ciclos, códigos únicos
  por empresa y límite de 32 niveles.
- Propagación de `ruta` al subárbol al mover un centro.
- RLS de `empresas`, `centros_costo` y `parques` por tenant y subárbol.
- Geocerca: rango de latitud/longitud y radio entre 1 y 10 000 m.
- Distancia haversine, tolerancia por precisión GPS (máximo 100 m) y
  fail-closed sin claims o con parque de otra empresa.
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
  activa. Un admin degradado deja de aprobar y de ver su antiguo equipo de
  inmediato, aunque su JWT aún no haya expirado.
- Geocerca congelada: al abrir la jornada se guardan latitud, longitud y radio
  del parque. El cierre acepta la geocerca actual o la foto de entrada, así que
  mover o redimensionar el parque durante el turno no atrapa al empleado. Un
  turno nuevo en la ubicación nueva ya no cierra en la anterior y el cliente no
  puede escribir la foto.
- Integridad cross-tenant: las FK de empleado en `jornadas` y
  `solicitudes_horas_extras` y la del revisor incluyen `empresa_id`. No se puede
  referenciar un perfil de otra empresa, borrar al revisor ni mover de empresa a
  un empleado con historial.
- Realtime: `jornadas` y `solicitudes_horas_extras` en la publicación
  `supabase_realtime` con `replica identity full`.
- Perfiles: materialización desde `app_metadata`, alcance inválido, cambio
  administrativo de rol y borrado en cascada.
- No autoelevación: `authenticated` no puede escribir `rol`, `empresa_id`,
  `empleado_id`, `centro_costo_id`, `ruta`, `actualizado_por` ni `auth.users`.
- Fail-closed: sin claims no hay acceso; `anon` no accede a ninguna tabla.
- Auditoría: `actualizado_en` y `actualizado_por`.

Resultado actual: **199 pruebas OK, 0 FAIL**.

## Límites

Esta suite valida el SQL de las migraciones, no el stack completo de Supabase:

- Los JWT son emulados con `request.jwt.claims`, no firmados por GoTrue.
- No ejecuta PostgREST ni comprueba los grants que Supabase añade por defecto.
- No sustituye a `supabase db reset` contra un proyecto Supabase real.

Antes de desplegar a producción, ejecutar las migraciones en un proyecto
Supabase de staging y repetir las pruebas de autoelevación con usuarios reales.
