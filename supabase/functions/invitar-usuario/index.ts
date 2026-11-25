// =============================================================================
// Carrousel — Edge Function: invitación de usuarios
//
// Punto de entrada HTTP. La lógica está separada por capas:
//   - `config.ts`         entorno y límites
//   - `respuestas.ts`     CORS y respuestas
//   - `validacion.ts`     cuerpo y claims del token
//   - `clientes.ts`       clientes de Supabase con timeout
//   - `autorizacion.ts`   sesión, perfil, empresa y subárbol
//   - `reconciliacion.ts` limpieza de cuentas huérfanas
//   - `servicio.ts`       orquestación de la invitación
//
// Seguridad:
//   - La plataforma valida el JWT del solicitante (verify_jwt por defecto).
//   - Solo un perfil activo con rol `admin` puede invitar.
//   - La empresa del admin debe seguir activa. La función usa `service_role`,
//     que ignora RLS: la suspensión de `0013` no aplica sola en esta ruta, así
//     que se verifica `empresas.activa` de forma explícita.
//   - El centro destino debe pertenecer a la empresa del admin y estar dentro
//     de su subárbol jerárquico. El `empresa_id` lo pone la función, no el
//     cliente.
//   - Los claims del JWT emitido deben coincidir con el perfil materializado.
//     Se lee el payload del token, no el registro actual de Auth, para que una
//     sesión vieja no herede un cambio de alcance.
//
// Despliegue:
//   supabase functions deploy invitar-usuario
//   supabase secrets set APP_REDIRECT_URL=io.supabase.carrousel://login-callback
// =============================================================================

import { verificarSesion } from "./autorizacion.ts";
import { clienteAdmin, clienteSolicitante } from "./clientes.ts";
import { leerConfiguracion, PUERTO } from "./config.ts";
import { CORS, error, respuestaFalloNoControlado } from "./respuestas.ts";
import { ejecutarInvitacion } from "./servicio.ts";
import type { InvitarBody } from "./tipos.ts";
import { validarCuerpo } from "./validacion.ts";

async function manejar(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  if (req.method !== "POST") {
    return error("Método no permitido.", 405);
  }

  const configuracion = leerConfiguracion();
  if (!configuracion) {
    return error("La función no está configurada correctamente.", 500);
  }

  const autorizacion = req.headers.get("Authorization");
  if (!autorizacion) {
    return error("Falta la sesión del administrador.", 401);
  }

  const solicitante = clienteSolicitante(
    configuracion.supabaseUrl,
    configuracion.anonKey,
    autorizacion,
  );
  const sesion = await verificarSesion(solicitante);
  if (sesion.respuesta) return sesion.respuesta;

  let cuerpo: InvitarBody;
  try {
    cuerpo = await req.json();
  } catch {
    return error("El cuerpo debe ser JSON válido.");
  }

  const validacion = validarCuerpo(cuerpo);
  if (validacion.mensaje !== null) return error(validacion.mensaje);

  const admin = clienteAdmin(
    configuracion.supabaseUrl,
    configuracion.serviceRoleKey,
  );
  return await ejecutarInvitacion({
    datos: validacion.datos,
    autorizacion,
    idUsuario: sesion.id,
    redirectTo: configuracion.redirectTo,
    admin,
  });
}

Deno.serve({ port: PUERTO }, async (req: Request) => {
  try {
    return await manejar(req);
  } catch (fallo) {
    return respuestaFalloNoControlado(fallo);
  }
});
