# Front de pruebas de Carrousel

Herramienta **independiente** para probar la API real de Supabase con botones,
formularios y una consola genérica. No toca Flutter ni la web existente, no usa
frameworks y no guarda credenciales, tokens ni URLs en el navegador ni en el
repositorio.

Archivos:

| Archivo | Uso |
|---|---|
| `index.html` | Interfaz: configuración, sesión, IDs de prueba, consultas, acciones, consola y registro. |
| `app.js` | Llamadas a Auth, PostgREST y la Edge Function con `fetch`. Estado solo en memoria. |
| `presets.mjs` | Catálogo de consultas y acciones con plantillas JSON. |
| `styles.css` | Estilos mínimos. |
| `test/presets.test.mjs` | Pruebas del catálogo y de que no se filtran secretos en el front. |

## 1. Requisitos

1. Un proyecto de Supabase con las migraciones `0001`–`0033` aplicadas.
2. La URL del proyecto y la **anon key**. Nunca la `service_role`.
3. Un servidor estático local. No abras el HTML con `file://`: usa, por ejemplo:

```bash
cd tools/front-pruebas
python -m http.server 5173
```

Luego abre `http://localhost:5173`.

Si el navegador bloquea la petición por CORS, añade `http://localhost:5173` a
**Authentication → URL Configuration → Redirect URLs** (y como Site URL si el
panel lo pide).

## 2. Preparar Supabase desde cero

### 2.1 Aplicar migraciones

Con Supabase CLI:

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db push
```

También puedes pegar las migraciones en orden en el SQL Editor del dashboard.
No edites migraciones ya mergeadas: si hace falta un cambio, crea una nueva.

### 2.2 Crear la empresa y el centro raíz

En el SQL Editor (el editor usa privilegios administrativos; esto **no** va en
el front ni en el cliente):

```sql
insert into public.empresas (codigo, nombre, nombre_comercial, zona_horaria)
values ('DEMO', 'Empresa Demo', 'Demo', 'America/Guatemala')
returning id;

insert into public.centros_costo (empresa_id, codigo, nombre)
values ('<uuid-empresa-devuelto-arriba>', 'RAIZ', 'Sede principal')
returning id;
```

El centro raíz debe tener `padre_id = NULL`; el trigger calcula `ruta`. Los
centros hijos sí se pueden crear desde el front con un admin.

### 2.3 Crear el primer administrador

1. En **Authentication → Add user**, crea el usuario con correo y contraseña de
   prueba y confírmalo (o desactiva la confirmación de correo solo en el proyecto
   de pruebas).
2. En el SQL Editor, asígnale el alcance. El trigger
   `on_auth_user_sync_perfil` materializa `public.perfiles`:

```sql
update auth.users u
set raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb)
      || jsonb_build_object('nombre_completo', 'Admin Demo'),
    raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb)
      || jsonb_build_object(
           'empresa_id', '<uuid-empresa>',
           'centro_costo_id', '<uuid-centro-raiz>',
           'rol', 'admin'
         )
where lower(u.email::text) = lower('<correo-admin>');

select id, email, raw_app_meta_data
from auth.users
where lower(email::text) = lower('<correo-admin>');

select id, empresa_id, centro_costo_id, rol, activo
from public.perfiles
where rol = 'admin';
```

Opcional, para dejar el centro con jefe vigente:

```sql
update public.centros_costo
set jefe_id = (select id from public.perfiles where rol = 'admin' limit 1)
where id = '<uuid-centro-raiz>';
```

3. En el front, **cierra sesión si ya habías entrado** y vuelve a iniciarla. El
   JWT solo refresca al entrar de nuevo; `Ver sesión y claims` debe mostrar
   `rol: admin`, `empresa_id` y `centro_costo_id`.

> Un empleado no puede hacer esto desde la app: `authenticated` no tiene
> `UPDATE` sobre `app_metadata` ni sobre `perfiles.rol`.

### 2.4 Desplegar la Edge Function de invitación

Sin CLI local, usa el workflow manual **Despliegue de Edge Function** con los
GitHub Secrets `SUPABASE_ACCESS_TOKEN` y `SUPABASE_DB_PASSWORD`, y los inputs
`project_ref` y `redirect_url`.

Con CLI local:

```bash
supabase functions deploy invitar-usuario
supabase secrets set APP_REDIRECT_URL=http://localhost:5173
```

`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y `SUPABASE_ANON_KEY` los inyecta
Supabase a la función. `AUTH_TIMEOUT_MS` es opcional (10000 ms por defecto).
Autoriza `http://localhost:5173` en Redirect URLs para que el correo de
invitación vuelva al front. La `service_role` **nunca** se escribe en esta
herramienta.

## 3. Puesta en marcha del front

1. Completa **URL de Supabase** y **anon key** y pulsa *Verificar configuración*.
2. Entra con el correo del admin. Pulsa *Ver sesión y claims* y comprueba el rol.
3. En **Valores de prueba**, pega al menos el centro raíz. Los marcadores se
   sustituyen solos:
   - `{{usuario}}` → `sub` del JWT.
   - `{{empresa}}` y `{{centro}}` → `app_metadata` del JWT, salvo que los pises a mano.
   - `{{parque}}`, `{{jornada}}`, `{{solicitud}}`, `{{registro}}`, `{{puesto}}`,
     `{{lat}}`, `{{lon}}`, `{{codigo_empresa}}` → campos de la sección 3.
4. Usa **Consultas rápidas** para ver tablas y vistas con la RLS del usuario
   actual. Si una consulta sale vacía, revisa los claims antes de sospechar del SQL.
5. En **Acciones**, elige una operación, edita el JSON si hace falta y pulsa
   *Ejecutar acción*. **Consola genérica** sirve para cualquier otra ruta o RPC.
6. Todo lo que envías y recibes aparece en **Registro**. Las contraseñas y los
   tokens de Auth se muestran como `[redactado]`.

## 4. Recorrido recomendado

### Admin

1. *Centros de costo* → copia el id del centro raíz al campo **Centro de prueba**.
2. *Crear parque*: pega latitud/longitud reales de tu zona, crea el parque y
   vuelve a *Parques* para copiar su id a **Parque de prueba**. Al crear el
   parque, el backend genera su CECO principal.
3. *Crear puesto*, *Crear centro hijo* y *Crear horario* para probar catálogos y
   jerarquía.
4. *Invitar empleado* con un correo nuevo. Abre el enlace del correo: si el
   redirect apunta al front, la sesión se toma del hash automáticamente. Si el
   proveedor usa PKCE (`?code=`), pega el access token en el campo manual.
5. *Horas extras* / *Registros por código*: cuando existan solicitudes, copia el
   id y usa *Aprobar* o *Rechazar*. Copia un id de jornada cerrada y prueba
   *Ajustar jornada*.
6. *Reporte de horas extras* y *Cumplimiento de jornadas*: comprueba los datos
   agregados y las incidencias calculadas.

### Empleado

Usa otra ventana de incógnito para no perder la sesión de admin.

1. Configura la misma URL y anon key. Con el correo invitado, entra con la
   contraseña que fijes tras aceptar la invitación. Si creas un usuario con
   *Crear usuario (signup)*, confirmalo desde el correo si hace falta.
2. *Ver sesión y claims* debe mostrar `rol: empleado` con la empresa y el centro
   asignados por el admin.
3. *Abrir jornada* con las coordenadas del parque: la base valida la geocerca.
4. *Cerrar jornada* con el id devuelto en **Jornada de prueba**.
5. *Crear horas extras*. Vuelta a la ventana de admin: *Aprobar horas extras*.
6. Para probar el alta por código, crea un tercer usuario con *signup*, entra con
   él y ejecuta *Solicitar alta por código* (sin perfil todavía). El admin ve la
   fila en *Registros por código* y ejecuta *Aprobar alta por código* o
   *Rechazar alta por código*. El usuario debe volver a entrar para obtener el
   JWT con el alcance recién escrito.

## 5. Pruebas y verificación

```bash
node tools/front-pruebas/test/presets.test.mjs
```

El arnés comprueba que no hay ids duplicados, que todas las acciones tienen
método/tipo/ruta válidos, que la interpolación funciona y que los archivos del
front no contienen `service_role`, secretos de Supabase ni URLs de proyecto.

## 6. Problemas habituales

| Síntoma | Causa probable |
|---|---|
| `401` o claims sin rol/empresa | Cerraste sesión antes de Promover al admin, o el JWT es anterior al cambio de `app_metadata`. Vuelve a entrar. |
| `403` en invitación o aprobación | El perfil no es admin activo, la empresa está inactiva o el centro está fuera del subárbol. |
| Consultas vacías | RLS: el token no tiene `app_metadata` completo o el usuario no es del tenant. |
| `La entrada/salida está fuera de la geocerca` | Las coordenadas no corresponden al parque o la precisión supera el umbral. |
| `Ya tienes un perfil aprovisionado` | *Solicitar alta por código* requiere un usuario sin perfil; usa otro correo. |
| El enlace de invitación llega con `?code=` | El front no canjea PKCE; usa un enlace con token o pega el access token. |
| Error de CORS | Añade `http://localhost:5173` a Redirect URLs y sirve por HTTP, no con `file://`. |
| `El registro ya fue resuelto` | Ya aprobaste/rechazaste esa fila; recarga y toma otro id. |

No subas a Git ningún correo, contraseña, token, URL real ni valor de
`service_role` que hayas usado al probar.
