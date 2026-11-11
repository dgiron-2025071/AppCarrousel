# Carrousel

Aplicación corporativa de **Carrousel** para registrar jornadas, validar el marcaje con GPS y gestionar solicitudes de horas extras con aprobación en tiempo real.

El núcleo se diseñó desde el inicio para escalar a toda la empresa sin datos hardcodeados: la jerarquía de centros de costo y parques es dinámica y el aislamiento entre empresas vive en la base de datos.

## Stack tecnológico

| Capa | Tecnología | Estado |
|---|---|---|
| Aplicación móvil | Flutter 3.47.9 / Dart 3.13.7, Riverpod, Material 3 | Implementada (login, dashboard, marcaje, horas extras, aprobaciones, perfil) |
| IDE móvil | Android Studio | Instalado en `C:\Program Files\Android\Android Studio` |
| Backend y base de datos | Supabase / PostgreSQL 17, RLS, Realtime | Migraciones `0001`–`0013` implementadas y validadas |
| Backend serverless | TypeScript sobre Deno (Supabase Edge Functions) | `invitar-usuario` implementada, verificada con `deno check` y 21 pruebas de integración |
| Tooling | pnpm 12.16.1, Supabase CLI 3.0.0, Git, GitHub CLI | Instalado |
| Mapas y geolocalización | OpenStreetMap + `flutter_map`, GPS nativo (`geolocator`) | Implementado con `InteractiveFlag.none` |
| Distribución Android | APK directo | `flutter build apk --debug` validado |

## Principios de arquitectura

- **Backend primero:** esquema, integridad referencial y RLS antes de conectar el cliente.
- **Multiempresa lógico:** `empresas` es la raíz; centros de costo y parques se crean por administración, sin hardcodear datos.
- **Jerarquía dinámica:** centros auto-referenciados con `ruta uuid[]`, FK compuesta por empresa y triggers anti-ciclos.
- **Seguridad en el servidor:** rol, `empresa_id` y `centro_costo_id` viven en `app_metadata` del JWT. Solo `service_role` los escribe; el cliente nunca decide su rol.
- **RLS como última línea:** `anon` y `authenticated` no tienen privilegios por defecto; cada tabla otorga permisos explícitos por columna.
- **Antifraude geográfico:** el GPS nativo envía coordenadas y precisión; PostgreSQL valida la geocerca y guarda `entrada_dentro_geocerca` / `salida_dentro_geocerca`. El mapa es informativo y no permite gestos.

## Roles

Solo existen dos roles de negocio, definidos por el enum cerrado `public.rol_usuario`:

| Rol | Alcance |
|---|---|
| `empleado` | Marca su jornada, consulta sus horas y crea solicitudes de horas extras. |
| `admin` | Todo lo anterior y, además, ve las solicitudes de los especialistas de su subárbol para aprobarlas o rechazarlas. |

No existe autoelevación: `authenticated` solo tiene `SELECT` sobre `public.perfiles`; el rol y el alcance los materializa un trigger desde `app_metadata`, escrito únicamente con `service_role`.

## Estado del backend — MT-01

- [x] **0001** Bootstrap: extensiones, schema `private`, enum `rol_usuario`, helpers JWT, auditoría y endurecimiento de grants.
- [x] **0002** `empresas` + jerarquía dinámica de `centros_costo` + RLS por subárbol.
- [x] **0003** `parques` + geocerca + RLS por alcance.
- [x] **0004** `perfiles` + sincronización desde `app_metadata` + RLS.
- [x] **0005** `jornadas` + distancia haversine + validación de geocerca + Realtime.
- [x] **0006** `solicitudes_horas_extras` + revisión administrativa por trigger + Realtime.
- [x] **0007** Endurecimiento operativo: cierre de jornada con parque desactivado, marcaje solo en el subárbol, perfiles inactivos sin escritura y precisión GPS no negativa.
- [x] **0008** Revocación inmediata de lectura del equipo para un admin inactivo, sin esperar a que expire su JWT.
- [x] **0009** Cierre de jornadas olvidadas de más de 24 h, sin dejar al empleado atrapado con una jornada abierta.
- [x] **0010** Estado `cancelada` para que el especialista retire una solicitud enviada por error.
- [x] **0011** RLS y trigger de retiro: solo el dueño cancela una solicitud pendiente y el admin deja de poder revisarla.
- [x] **0012** Retención del historial: borrar una cuenta con jornadas o solicitudes se bloquea (`ON DELETE RESTRICT`); la baja de personal se hace desactivando el perfil.
- [x] **0013** Suspensión efectiva de empresas inactivas: `current_empresa_id()` falla cerrado y corta lectura y escritura del tenant de inmediato.
- [x] Arnés de validación con PostgreSQL 17.9 portátil y emulación de roles/`auth` de Supabase.
- [x] **180 pruebas automáticas OK, 0 fallos** (`pnpm --dir tools/db-validation test`).
- [x] Invitación automática de administradores con Edge Function y `service_role` (`supabase/functions/invitar-usuario`).
- [x] Verificación estática de la Edge Function con `deno check`, `deno lint` y `deno fmt --check`.
- [x] **21 pruebas de integración de la Edge Function OK, 0 fallos** (`npx -y deno test -A supabase/functions/tests/invitar_usuario_test.ts`), con un Supabase falso local.
- [ ] Despliegue y prueba de la Edge Function contra un proyecto Supabase real (requiere credenciales).
- [ ] Validación con `supabase db reset` y JWT reales de Supabase (requiere Docker/WSL2).

> El arnés levanta un PostgreSQL real y aplica las migraciones, pero emula los claims con `request.jwt.claims` y el esquema `auth`. La validación con JWT firmados por Supabase queda pendiente por no contar con Docker/WSL2 en el entorno.

### Flujo de aprovisionamiento

1. Un administrador autorizado genera una invitación con rol (`empleado` o `admin`) y alcance (`empresa_id`, `centro_costo_id`).
2. Una Edge Function con `service_role` crea el usuario en Supabase Auth y escribe esos valores en `app_metadata`.
3. El trigger `on_auth_user_sync_perfil` materializa `public.perfiles` al crear el usuario o al cambiar `app_metadata`.
4. RLS y los grants por columna impiden que el usuario modifique su rol o su alcance.

### Invitación de usuarios

La función `supabase/functions/invitar-usuario` recibe `email`, `nombre_completo`, `rol` y `centro_costo_id`, y:

- exige una sesión válida y un perfil **activo** con rol `admin`;
- toma `empresa_id` del perfil del administrador, nunca del cuerpo;
- comprueba que el centro destino esté en su subárbol (`ruta`) y en su empresa;
- invita por correo, escribe `app_metadata` con `service_role` y revierte el usuario si falla la asignación.

El detalle del contrato y los comandos de despliegue están en [`supabase/functions/README.md`](supabase/functions/README.md). La función está verificada con `deno check` y 21 pruebas de integración contra un Supabase falso local (sesión, perfil, jerarquía, validaciones, invitación, claims y rollback); su despliegue y prueba contra un proyecto real quedan pendientes de credenciales.

## Aplicación móvil

La app arranca siempre en la pantalla de inicio de sesión: **no hay usuarios ni sesiones de ejemplo**. Toda cuenta debe existir previamente en Supabase Auth.

### Funcionalidad implementada

- **Login** con correo/contraseña, recuperación de contraseña y **Continuar con Google** (OAuth con PKCE y deep link).
- **Dashboard del empleado** con horas de hoy, semana y mes, jornada en curso y últimos marcajes; se actualiza con Realtime.
- **Marcaje de entrada/salida** con `flutter_map` + OpenStreetMap, GPS nativo y selección del parque. El mapa usa `InteractiveFlag.none`; la geocerca se valida en PostgreSQL. Si el parque se desactiva durante el turno, la app conserva ese parque para poder cerrar la jornada y no lo ofrece para nuevas entradas.
- **Horas extras:** rango de horas, parque/centro de costo donde apoyó y justificación. La solicitud nace `pendiente`.
- **Historial propio** de solicitudes con estado, comentario del administrador y actualización en tiempo real. El especialista puede retirar una solicitud mientras siga pendiente; la cancelación conserva el historial.
- **Aprobaciones del admin:** solicitudes del subárbol con nombre del especialista, justificación, rango y comentario opcional al aprobar o rechazar. El resultado le llega al especialista por Realtime.
- **Perfil:** datos de la cuenta, cambio de contraseña y cierre de sesión.
- **Invitación de usuarios (admin):** correo, nombre, rol y centro de costo dentro de su subárbol. La pantalla consume la Edge Function `invitar-usuario`, muestra los errores del servidor y calcula el subárbol con la jerarquía dinámica de `centros_costo` (sin datos hardcodeados).

### Estructura

```text
apps/mobile/lib/
├── core/            # configuración, tema, errores, utilidades y widgets
├── data/            # modelos y repositorios Supabase
├── providers/       # providers de Riverpod, streams Realtime y catálogos
├── features/        # auth, shell, dashboard, jornada, solicitudes, admin, perfil
└── main.dart        # Supabase.initialize + ProviderScope
```

## Configuración de la app

Las credenciales se inyectan en tiempo de compilación; nunca se versionan:

```bash
cd apps/mobile
flutter run \
  --dart-define=SUPABASE_URL=https://tu-proyecto.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=tu-clave-publica
```

Si faltan las credenciales, la app muestra una pantalla de configuración con el comando exacto y no intenta conectarse.

### Supabase Auth

1. Habilita el proveedor **Google** en `Authentication > Providers`.
2. Autoriza el redirect `io.supabase.carrousel://login-callback` en `Authentication > URL Configuration`.
3. Para recuperación de contraseña, el correo debe regresar a ese mismo deep link. El intent-filter ya está declarado en `apps/mobile/android/app/src/main/AndroidManifest.xml`.

### Android

- Permisos declarados: `INTERNET`, `ACCESS_FINE_LOCATION` y `ACCESS_COARSE_LOCATION` (solo ubicación en primer plano).
- Label visible: **Carrousel**.
- Application ID: `com.empresacarrousel.carrousel_app`.

## Validación de la base de datos

El arnés vive en `tools/db-validation` y usa `embedded-postgres` para ejecutar PostgreSQL 17.9 portátil sin Docker:

```bash
pnpm --dir tools/db-validation test
```

Cubre jerarquía dinámica y anti-ciclos, aislamiento por empresa, RLS de perfiles/centros/parques/jornadas/solicitudes, no autoelevación, geocerca con tolerancia GPS, una sola jornada abierta, coherencia de la revisión y prohibición de revisar solicitudes propias o ya revisadas. Las migraciones `0007`–`0013` añaden pruebas para el cierre de jornada con parque desactivado, el marcaje fuera del subárbol, los perfiles inactivos, la precisión GPS negativa, la revocación inmediata de lectura para un admin desactivado, el cierre de una jornada olvidada de más de 24 h, el retiro de solicitudes propias, la retención del historial ante el borrado de cuentas y el corte inmediato de acceso para una empresa inactiva. Resultado actual: **180 pruebas OK, 0 fallos**.

La Edge Function se verifica sin desplegarla:

```bash
npx -y deno check supabase/functions/invitar-usuario/index.ts
npx -y deno lint supabase/functions/invitar-usuario/index.ts
npx -y deno fmt --check supabase/functions/invitar-usuario/index.ts
npx -y deno test -A supabase/functions/tests/invitar_usuario_test.ts
```

Las pruebas de integración levantan un servidor que emula Supabase Auth/PostgREST y ejecutan la función en un puerto libre. Cubren CORS, sesión, perfil, validaciones del cuerpo, empresa y subárbol, invitación de empleado/admin, correo duplicado, error de envío y rollback al fallar `app_metadata`. Resultado actual: **21 pruebas OK, 0 fallos**.

## Historial de cambios

| Fecha | Entrega | Rama | PR | Estado | Validación |
|---|---|---|---|---|---|
| 2026-11-05 | Migración `0001` — bootstrap de extensiones y helpers de seguridad | `dgiron-2025071` | [#2](https://github.com/dgiron-2025071/AppCarrousel/pull/2) | Mergeado a `develop` | Revisión estática |
| 2026-11-05 | README con stack, estado y bitácora | `dgiron-2025071` | [#3](https://github.com/dgiron-2025071/AppCarrousel/pull/3) | Mergeado a `develop` | — |
| 2026-11-05 | Scaffold Flutter en `apps/mobile` | `dgiron-2025071` | [#4](https://github.com/dgiron-2025071/AppCarrousel/pull/4) | Mergeado a `develop` | `flutter analyze` |
| 2026-11-05 | Pantalla de botones (preview) | `dgiron-2025071` | [#5](https://github.com/dgiron-2025071/AppCarrousel/pull/5) | Mergeado a `develop` | `flutter analyze` + APK debug |
| 2026-11-05 | README: estado del móvil y entorno | `dgiron-2025071` | [#6](https://github.com/dgiron-2025071/AppCarrousel/pull/6) | Mergeado a `develop` | — |
| 2026-11-05 | Migración `0002` — empresas y centros de costo | `dgiron-2025071` | [#7](https://github.com/dgiron-2025071/AppCarrousel/pull/7) | Mergeado a `develop` | Revisión estática |
| 2026-11-05 | README: registrar migración `0002` | `dgiron-2025071` | [#8](https://github.com/dgiron-2025071/AppCarrousel/pull/8) | Mergeado a `develop` | — |
| 2026-11-05 | Migración `0003` — parques y geocerca | `dgiron-2025071` | [#9](https://github.com/dgiron-2025071/AppCarrousel/pull/9) | Mergeado a `develop` | Revisión estática |
| 2026-11-05 | README: registrar migración `0003` | `dgiron-2025071` | [#10](https://github.com/dgiron-2025071/AppCarrousel/pull/10) | Mergeado a `develop` | — |
| 2026-11-05 | Migración `0004` — perfiles y roles | `dgiron-2025071` | [#11](https://github.com/dgiron-2025071/AppCarrousel/pull/11) | Mergeado a `develop` | Revisión estática |
| 2026-11-05 | README: registrar migración `0004` y cierre del esquema | `dgiron-2025071` | [#12](https://github.com/dgiron-2025071/AppCarrousel/pull/12) | Mergeado a `develop` | — |
| 2026-11-05 | README: historial y deuda de validación | `dgiron-2025071` | [#13](https://github.com/dgiron-2025071/AppCarrousel/pull/13) | Mergeado a `develop` | — |
| 2026-11-06 | Roles `empleado`/`admin` y correcciones de jerarquía | `dgiron-2025071` | [#15](https://github.com/dgiron-2025071/AppCarrousel/pull/15) | Mergeado a `develop` | Revisión estática |
| 2026-11-06 | Arnés de validación con PostgreSQL portátil | `dgiron-2025071` | [#16](https://github.com/dgiron-2025071/AppCarrousel/pull/16) | Mergeado a `develop` | 144 pruebas |
| 2026-11-06 | Migración `0005` — jornadas y geocerca | `dgiron-2025071` | [#17](https://github.com/dgiron-2025071/AppCarrousel/pull/17) | Mergeado a `develop` | 144 pruebas OK |
| 2026-11-06 | Migración `0006` — horas extras y aprobación | `dgiron-2025071` | [#18](https://github.com/dgiron-2025071/AppCarrousel/pull/18) | Mergeado a `develop` | 144 pruebas OK |
| 2026-11-06 | App Flutter conectada a Supabase + Edge Function de invitación | `dgiron-2025071` | [#19](https://github.com/dgiron-2025071/AppCarrousel/pull/19) | Mergeado a `develop` | `flutter analyze`, APK debug, `deno check` |
| 2026-11-09 | Pruebas de integración de la Edge Function de invitación | `dgiron-2025071` | [#21](https://github.com/dgiron-2025071/AppCarrousel/pull/21) | Mergeado a `develop` | 21 pruebas Deno OK |
| 2026-11-09 | Finales de línea LF para validaciones reproducibles | `dgiron-2025071` | [#22](https://github.com/dgiron-2025071/AppCarrousel/pull/22) | Mergeado a `develop` | `deno fmt --check` |
| 2026-11-09 | Pantalla de invitación de usuarios para administradores | `dgiron-2025071` | [#23](https://github.com/dgiron-2025071/AppCarrousel/pull/23) | Mergeado a `develop` | `flutter analyze`, 5 pruebas, APK debug |
| 2026-11-09 | Pruebas de invitación y subárboles en Flutter | `dgiron-2025071` | [#25](https://github.com/dgiron-2025071/AppCarrousel/pull/25) | Mergeado a `develop` | 18 pruebas, `flutter analyze`, APK debug |
| 2026-11-09 | Migración `0007` — endurecimiento operativo del backend | `dgiron-2025071` | [#26](https://github.com/dgiron-2025071/AppCarrousel/pull/26) | Mergeado a `develop` | 155 pruebas OK |
| 2026-11-09 | Migración `0008` — revocación de lectura para admin inactivo | `dgiron-2025071` | [#28](https://github.com/dgiron-2025071/AppCarrousel/pull/28) | Mergeado a `develop` | 159 pruebas OK |
| 2026-11-10 | Migración `0009` — cierre de jornadas olvidadas | `dgiron-2025071` | [#30](https://github.com/dgiron-2025071/AppCarrousel/pull/30) | Mergeado a `develop` | 160 pruebas OK |
| 2026-11-10 | Migraciones `0010`/`0011` — retiro de solicitudes pendientes | `dgiron-2025071` | [#31](https://github.com/dgiron-2025071/AppCarrousel/pull/31) | Mergeado a `develop` | 166 pruebas OK |
| 2026-11-11 | App: cierre de jornada si el parque se desactiva | `dgiron-2025071` | [#34](https://github.com/dgiron-2025071/AppCarrousel/pull/34) | Mergeado a `develop` | `flutter analyze`, 28 pruebas |
| 2026-11-11 | Migración `0012` — retención del historial laboral | `dgiron-2025071` | [#35](https://github.com/dgiron-2025071/AppCarrousel/pull/35) | Mergeado a `develop` | 169 pruebas OK |
| 2026-11-11 | Migración `0013` — suspensión de empresas inactivas | `dgiron-2025071` | [#36](https://github.com/dgiron-2025071/AppCarrousel/pull/36) | Mergeado a `develop` | 180 pruebas OK |

> Nota de proceso: el PR #1 se creó como borrador y GitHub devolvió un error de GraphQL al intentar marcarlo como listo. Se cerró y se recreó como PR #2. El PR #14 no existe.

## Flujo Git

1. Rama de trabajo: `dgiron-2025071`.
2. Commits agrupados por entregable.
3. Push a `origin/dgiron-2025071`.
4. Pull Request hacia `develop`.
5. Merge validado a `develop`.
6. Al cerrar la micro-tarea: Pull Request de `develop` hacia `main`.

No se hace push directo a `main`. Cada merge a `develop` deja la rama de trabajo sincronizada antes del siguiente entregable.

## Entorno local

| Herramienta | Versión / estado |
|---|---|
| Flutter | 3.47.9 (stable) |
| Dart | 3.13.7 |
| Android Studio | Instalado |
| Android SDK | 36 (platform 36 rev.2) |
| Android NDK | 28.2.13676358 |
| Emulador | `Medium_Phone_API_37.0` |
| Node.js | 22.22.3 |
| pnpm | 12.16.1 |
| Supabase CLI | 3.0.0 |
| Docker Desktop | Pendiente (requiere WSL2 y elevación) |

### Abrir el proyecto móvil

Abrir en Android Studio la carpeta `apps/mobile` (no la raíz del repo):

```text
File > Open... > C:\AppCarrousel\apps\mobile
```

### Comandos

```bash
# Validación real de las migraciones (PostgreSQL portátil, sin Docker)
pnpm --dir tools/db-validation test

# Pruebas de integración de la Edge Function (Supabase falso, sin credenciales)
npx -y deno test -A supabase/functions/tests/invitar_usuario_test.ts

# Backend con Supabase local (cuando Docker esté disponible)
supabase start
supabase db reset

# Móvil
cd apps/mobile
flutter pub get
flutter analyze
flutter build apk --debug
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Siguientes pasos

1. Desplegar `invitar-usuario` en el proyecto Supabase real y probar el flujo completo de invitación con correo.
2. Validar las migraciones con `supabase db reset` y JWT reales de Supabase cuando Docker/WSL2 esté disponible.
3. Ampliar las pruebas de widget/unitarias de la app Flutter (ya existen pruebas de subárboles, selección de parques para cierre, errores de la función y pantalla de invitación).
4. Cerrar MT-01 con el merge de `develop` a `main`.

## Seguridad

- La clave `service_role` nunca se incluye en la app móvil; solo se usa en Edge Functions o administración.
- `user_metadata` no se usa para autorización; el rol y el alcance viven en `app_metadata`.
- Las migraciones se versionan; no se hacen cambios manuales de esquema en el dashboard.
- Las políticas RLS y los grants se revisan antes de cada merge.
- La baja de personal se hace desactivando `public.perfiles.activo`, no borrando la cuenta: las FK con `ON DELETE RESTRICT` impiden perder jornadas y solicitudes.
- Desactivar `public.empresas.activa` corta de inmediato todo el tenant: `current_empresa_id()` devuelve NULL y las políticas fallan cerradas.
- La app no incluye usuarios, contraseñas ni sesiones de ejemplo.
