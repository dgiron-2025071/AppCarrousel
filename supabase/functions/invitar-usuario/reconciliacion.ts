// Capa de reconciliacion: limpia solo la cuenta huérfana que GoTrue pudo dejar
// al crear el usuario y fallar despues el envio del correo.

import type { ClienteSupabase } from "./clientes.ts";
import {
  MAX_PAGINAS_USUARIOS,
  USUARIOS_POR_PAGINA,
  VENTANA_HUERFANO_MS,
} from "./config.ts";
import { esTimeout } from "./errores.ts";

export type ResultadoReconciliacion =
  | "limpio"
  | "revertido"
  | "error"
  | "timeout";

export async function reconciliarInvitacionFallida(
  admin: ClienteSupabase,
  email: string,
): Promise<ResultadoReconciliacion> {
  try {
    const ahora = Date.now();
    let pagina = 1;

    while (true) {
      if (pagina > MAX_PAGINAS_USUARIOS) {
        console.error(
          "ALERTA: se agotó el techo de páginas al buscar la huérfana de",
          email,
        );
        return "error";
      }

      const { data, error: listError } = await admin.auth.admin.listUsers({
        page: pagina,
        perPage: USUARIOS_POR_PAGINA,
      });
      if (listError || !data) {
        return esTimeout(listError) ? "timeout" : "error";
      }

      const usuarios = Array.isArray(data.users) ? data.users : [];
      const huerfano = usuarios.find((usuario) => {
        const creado = Date.parse(usuario.created_at ?? "");
        return usuario.email?.toLowerCase() === email &&
          !usuario.app_metadata?.empresa_id &&
          Number.isFinite(creado) &&
          ahora - creado >= 0 &&
          ahora - creado <= VENTANA_HUERFANO_MS;
      });

      if (huerfano) {
        const { error: deleteError } = await admin.auth.admin
          .deleteUser(huerfano.id);
        if (deleteError) {
          console.error(
            "ALERTA: no se pudo limpiar la invitación huérfana de",
            email,
            deleteError.message,
          );
          return esTimeout(deleteError) ? "timeout" : "error";
        }
        return "revertido";
      }

      const siguiente = (data as { nextPage?: number | null }).nextPage;
      if (typeof siguiente === "number") {
        if (siguiente <= pagina || siguiente > MAX_PAGINAS_USUARIOS) {
          console.error(
            "ALERTA: paginación de Auth inconsistente para",
            email,
            `pagina=${pagina} siguiente=${siguiente}`,
          );
          return "error";
        }
        pagina = siguiente;
        continue;
      }

      if (usuarios.length < USUARIOS_POR_PAGINA) return "limpio";
      pagina += 1;
    }
  } catch (error) {
    console.error("ALERTA: falló la reconciliación de", email, error);
    return esTimeout(error) ? "timeout" : "error";
  }
}
