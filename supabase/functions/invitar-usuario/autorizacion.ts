// Capa de autorizacion: sesion, perfil vigente, claims del JWT, empresa activa
// y subarbol del centro destino. No crea ni modifica usuarios.

import type { ClienteSupabase } from "./clientes.ts";
import { esTimeout } from "./errores.ts";
import { error } from "./respuestas.ts";
import type {
  CentroDestino,
  ContextoAutorizado,
  EmpresaSolicitante,
  PerfilSolicitante,
} from "./tipos.ts";
import { claimsDelToken } from "./validacion.ts";

export type ResultadoSesion =
  | { id: string; respuesta: null }
  | { id: null; respuesta: Response };

export async function verificarSesion(
  cliente: ClienteSupabase,
): Promise<ResultadoSesion> {
  const { data: authData, error: authError } = await cliente.auth.getUser();
  if (esTimeout(authError)) {
    return {
      id: null,
      respuesta: error(
        "Auth no respondió al verificar la sesión. Intenta de nuevo.",
        504,
      ),
    };
  }
  if (authError || !authData.user) {
    return {
      id: null,
      respuesta: error("Sesión inválida o expirada.", 401),
    };
  }
  return { id: authData.user.id, respuesta: null };
}

export type ResultadoAutorizacion =
  | { contexto: ContextoAutorizado; respuesta: null }
  | { contexto: null; respuesta: Response };

export async function autorizar(
  admin: ClienteSupabase,
  autorizacion: string,
  idUsuario: string,
  centroId: string,
): Promise<ResultadoAutorizacion> {
  const { data: perfiles, error: perfilError } = await admin
    .from("perfiles")
    .select("empresa_id, centro_costo_id, rol, activo")
    .eq("id", idUsuario)
    .limit(1);

  if (perfilError) {
    return {
      contexto: null,
      respuesta: esTimeout(perfilError)
        ? error("La base de datos no respondió al leer el perfil.", 504)
        : error("No se pudo verificar el perfil del solicitante.", 500),
    };
  }
  const perfil = (perfiles?.[0] ?? null) as PerfilSolicitante | null;
  if (!perfil || perfil.rol !== "admin" || !perfil.activo) {
    return {
      contexto: null,
      respuesta: error(
        "Solo un administrador activo puede invitar usuarios.",
        403,
      ),
    };
  }

  // El alcance autorizado es el del JWT (`app_metadata`), igual que en la base
  // de datos (`0017`). Si el perfil fue degradado o movido sin refrescar la
  // sesión, la función falla cerrada en lugar de ampliar el alcance.
  const claims = claimsDelToken(autorizacion);
  if (!claims || claims.sub !== idUsuario) {
    return {
      contexto: null,
      respuesta: error("Sesión inválida o expirada.", 401),
    };
  }
  const appMetadata = (claims.app_metadata ?? {}) as Record<string, unknown>;
  if (
    appMetadata.rol !== "admin" ||
    appMetadata.empresa_id !== perfil.empresa_id ||
    appMetadata.centro_costo_id !== perfil.centro_costo_id
  ) {
    return {
      contexto: null,
      respuesta: error(
        "Tu sesión ya no refleja tu alcance actual. Vuelve a iniciar sesión.",
        403,
      ),
    };
  }

  // `service_role` ignora RLS: la suspensión de la empresa (0013) no basta.
  const { data: empresas, error: empresaError } = await admin
    .from("empresas")
    .select("activa")
    .eq("id", perfil.empresa_id)
    .limit(1);

  if (empresaError) {
    return {
      contexto: null,
      respuesta: esTimeout(empresaError)
        ? error("La base de datos no respondió al leer la empresa.", 504)
        : error("No se pudo verificar la empresa.", 500),
    };
  }
  const empresa = (empresas?.[0] ?? null) as EmpresaSolicitante | null;
  if (!empresa?.activa) {
    return {
      contexto: null,
      respuesta: error("La empresa está suspendida.", 403),
    };
  }

  const { data: centros, error: centroError } = await admin
    .from("centros_costo")
    .select("id, empresa_id, ruta")
    .eq("id", centroId)
    .limit(1);

  if (centroError) {
    return {
      contexto: null,
      respuesta: esTimeout(centroError)
        ? error(
          "La base de datos no respondió al leer el centro de costo.",
          504,
        )
        : error("No se pudo verificar el centro de costo.", 500),
    };
  }
  const centro = (centros?.[0] ?? null) as CentroDestino | null;
  if (!centro || centro.empresa_id !== perfil.empresa_id) {
    return {
      contexto: null,
      respuesta: error("El centro de costo no pertenece a tu empresa.", 400),
    };
  }

  const ruta = centro.ruta ?? [];
  const enAlcance = centro.id === perfil.centro_costo_id ||
    ruta.includes(perfil.centro_costo_id);
  if (!enAlcance) {
    return {
      contexto: null,
      respuesta: error(
        "Solo puedes invitar usuarios a centros dentro de tu subárbol.",
        403,
      ),
    };
  }

  return { contexto: { perfil, centro }, respuesta: null };
}
