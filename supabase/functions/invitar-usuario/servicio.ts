// Capa de servicio: orquesta autorizacion, invitacion, escritura de claims,
// rollback y reconciliacion. No conoce CORS ni el parseo del request.

import { autorizar } from "./autorizacion.ts";
import type { ClienteSupabase } from "./clientes.ts";
import { esTimeout } from "./errores.ts";
import { reconciliarInvitacionFallida } from "./reconciliacion.ts";
import { error, json } from "./respuestas.ts";
import type { DatosInvitacion } from "./tipos.ts";

export interface ParametrosInvitacion {
  datos: DatosInvitacion;
  autorizacion: string;
  idUsuario: string;
  redirectTo: string;
  admin: ClienteSupabase;
}

export async function ejecutarInvitacion(
  parametros: ParametrosInvitacion,
): Promise<Response> {
  const { datos, autorizacion, idUsuario, redirectTo, admin } = parametros;
  const { email, nombre, rol, centroId } = datos;

  const autorizacionResultado = await autorizar(
    admin,
    autorizacion,
    idUsuario,
    centroId,
  );
  if (autorizacionResultado.respuesta) return autorizacionResultado.respuesta;
  const { perfil, centro } = autorizacionResultado.contexto!;

  const { data: invitacion, error: invitacionError } = await admin.auth.admin
    .inviteUserByEmail(email, { redirectTo });

  if (invitacionError || !invitacion.user) {
    const texto = (invitacionError?.message ?? "").toLowerCase();
    if (
      texto.includes("already been registered") ||
      texto.includes("already exists")
    ) {
      return error("Ese correo ya tiene una cuenta en Carrousel.", 409);
    }
    const timeoutInvitacion = esTimeout(invitacionError);
    if (timeoutInvitacion) {
      console.error("ALERTA: timeout al invitar a", email, invitacionError);
    }
    const reconciliacion = await reconciliarInvitacionFallida(admin, email);
    if (reconciliacion === "error") {
      return error(
        "No se pudo enviar la invitación ni verificar si quedó una cuenta huérfana. Revisa Auth.",
        500,
      );
    }
    if (reconciliacion === "timeout") {
      return error(
        "Auth no respondió al buscar una cuenta huérfana. Revisa Auth antes de reintentar.",
        504,
      );
    }
    if (reconciliacion === "revertido") {
      return error(
        "No se pudo enviar la invitación. Se eliminó la cuenta huérfana; vuelve a intentar.",
        502,
      );
    }
    if (timeoutInvitacion) {
      return error(
        "Auth no respondió al enviar la invitación; no se confirmó si se creó la cuenta. Revisa Auth antes de reintentar.",
        504,
      );
    }
    return error(
      "No se pudo enviar la invitación. Revisa la configuración de correo.",
      502,
    );
  }

  const { error: claimsError } = await admin.auth.admin.updateUserById(
    invitacion.user.id,
    {
      app_metadata: {
        empresa_id: perfil.empresa_id,
        centro_costo_id: centro.id,
        rol,
      },
      user_metadata: { nombre_completo: nombre },
    },
  );

  if (claimsError) {
    // Un timeout NO prueba que la escritura falló: pudo haberse aplicado y
    // perderse la respuesta. Borrar al usuario aquí dejaría sin invitación a
    // alguien cuyo alcance quizá ya quedó grabado. Se reporta y se pide
    // revisión manual en vez de afirmar una reversión.
    if (esTimeout(claimsError)) {
      console.error(
        "ALERTA: timeout al asignar el alcance de",
        invitacion.user.id,
        claimsError,
      );
      return error(
        "No se pudo confirmar la asignación de alcance. Revisa el usuario en Auth antes de reintentar.",
        504,
      );
    }

    // Rollback: no se deja un usuario de Auth sin perfil ni alcance. Si la
    // reversión también falla, decirlo explícitamente para que el admin sepa
    // que queda una cuenta huérfana que hay que revisar a mano.
    const { error: rollbackError } = await admin.auth.admin
      .deleteUser(invitacion.user.id);

    if (rollbackError) {
      console.error(
        "ALERTA: no se pudo revertir la invitación de",
        invitacion.user.id,
        rollbackError.message,
      );
      return error(
        "No se pudo asignar el alcance ni revertir la invitación. Revisa el usuario creado en Auth.",
        esTimeout(rollbackError) ? 504 : 500,
      );
    }

    return error(
      "No se pudo asignar el alcance al usuario. La invitación se revirtió.",
      500,
    );
  }

  return json(
    {
      id: invitacion.user.id,
      email,
      rol,
      empresa_id: perfil.empresa_id,
      centro_costo_id: centro.id,
      nombre_completo: nombre,
      invitacion_enviada: true,
    },
    201,
  );
}
