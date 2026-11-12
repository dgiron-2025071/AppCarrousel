# Edge Functions

## `invitar-usuario`

Crea un usuario en Supabase Auth mediante invitación por correo y escribe en
`app_metadata` el alcance (`empresa_id`, `centro_costo_id`) y el rol
(`empleado` o `admin`). El trigger `on_auth_user_sync_perfil` materializa
`public.perfiles`; el cliente nunca escribe esos claims.

### Reglas de seguridad

- La función se despliega con verificación de JWT activada (`verify_jwt`).
- Además, la función vuelve a validar el usuario con `auth.getUser()`.
- Solo un perfil **activo** con rol `admin` puede invitar.
- Los claims del JWT deben seguir vigentes: `rol = admin`, `empresa_id` y
  `centro_costo_id` iguales al perfil materializado. La función lee el payload
  del token ya validado por la plataforma, no el registro actual de Auth, para
  que un token emitido antes de un cambio de alcance falle cerrado. Si no
  coinciden, responde `403` y pide volver a iniciar sesión, igual que
  `private.es_admin()` en la base (`0017`).
- La empresa del admin debe seguir **activa**. La función usa `service_role`,
  que ignora RLS, así que la suspensión de la empresa (`0013`) se verifica de
  forma explícita antes de enviar la invitación.
- El centro destino debe pertenecer a la empresa del admin y estar en su
  subárbol jerárquico (`ruta` del centro). El `empresa_id` lo determina la
  función a partir del perfil del solicitante, no el cuerpo de la petición.
- Si falla la escritura de `app_metadata`, el usuario recién invitado se borra
  para no dejar una cuenta sin alcance.
- No se usa `user_metadata` para autorización.

### Cuerpo de la petición

```json
{
  "email": "especialista@empresa.com",
  "nombre_completo": "Nombre Apellido",
  "rol": "empleado",
  "centro_costo_id": "00000000-0000-0000-0000-000000000000"
}
```

### Despliegue

```bash
supabase login
supabase link --project-ref <project-ref>
supabase functions deploy invitar-usuario
supabase secrets set APP_REDIRECT_URL=io.supabase.carrousel://login-callback
```

El redirect debe estar autorizado en `Authentication > URL Configuration`.
La función usa `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y
`SUPABASE_ANON_KEY`, que Supabase inyecta automáticamente en el entorno de la
función.

### Invocación

Con la sesión de un administrador:

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/invitar-usuario" \
  -H "Authorization: Bearer <access-token-del-admin>" \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "especialista@empresa.com",
    "nombre_completo": "Nombre Apellido",
    "rol": "empleado",
    "centro_costo_id": "<uuid-del-centro>"
  }'
```

Respuesta `201`:

```json
{
  "id": "<uuid>",
  "email": "especialista@empresa.com",
  "rol": "empleado",
  "empresa_id": "<uuid>",
  "centro_costo_id": "<uuid>",
  "nombre_completo": "Nombre Apellido",
  "invitacion_enviada": true
}
```

### Validación local

Verificación estática:

```bash
npx -y deno check supabase/functions/invitar-usuario/index.ts
npx -y deno lint supabase/functions/invitar-usuario/index.ts
npx -y deno fmt --check supabase/functions/invitar-usuario/index.ts
```

Pruebas de integración (no requieren credenciales ni Docker):

```bash
npx -y deno test -A supabase/functions/tests/invitar_usuario_test.ts
```

El arnés levanta un servidor HTTP que emula los endpoints de Supabase Auth y
PostgREST usados por la función, arranca `invitar-usuario` como subproceso en un
puerto libre (`PORT`) y verifica **31 escenarios**:

- CORS, método distinto de `POST` y ausencia o invalidez de la sesión.
- Perfil inexistente, inactivo, con rol distinto de `admin` o con error de
  consulta.
- Claims del token degradados o desalineados con el perfil (`rol`, `empresa_id`
  o `centro_costo_id`), token sin forma de JWT o emitido para otro usuario, sin
  enviar la invitación.
- El payload del token manda sobre el registro actual de Auth: un token viejo no
  hereda el alcance nuevo del perfil y un registro desalineado no invalida un
  token correcto.
- Empresa suspendida o inexistente (`403`) y error al consultarla (`500`), sin
  enviar la invitación.
- Validaciones de JSON, correo, nombre, rol y UUID del centro.
- Centro de otra empresa, centro fuera del subárbol y error al consultarlo.
- Invitación exitosa de `empleado` y de `admin`, comprobando que
  `empresa_id` sale del perfil del solicitante y no del cuerpo.
- Correo ya registrado (`409`), error genérico de invitación (`502`).
- Error al escribir `app_metadata`: responde `500` y borra el usuario invitado
  (rollback verificado).

Las consultas de perfil y centro usan `.limit(1)` en lugar de `.maybeSingle()`
para que el contrato con PostgREST sea explícito y no dependa de códigos
`406/PGRST116`.

El despliegue y la prueba contra un proyecto Supabase real quedan pendientes de
credenciales; no se versionan claves ni tokens.
