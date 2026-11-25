// Capa de configuracion: unico lugar que lee el entorno.

export const REDIRECT_POR_DEFECTO = "io.supabase.carrousel://login-callback";

// GoTrue puede crear el usuario y fallar después al enviar el correo; en ese
// caso responde sin el id. Solo se considera huérfana una cuenta del mismo
// correo, creada en los últimos 10 minutos y sin app_metadata.empresa_id.
export const VENTANA_HUERFANO_MS = 10 * 60 * 1000;

// `listUsers` admite paginacion: recorremos `nextPage` hasta agotarla. El
// techo evita un bucle infinito si Auth devuelve punteros repetidos; al
// alcanzarlo se falla cerrado en vez de afirmar que no habia huérfana.
export const USUARIOS_POR_PAGINA = 100;
export const MAX_PAGINAS_USUARIOS = 20;

// Limite de espera por llamada a Auth/PostgREST. Sin el, una peticion colgada
// mantiene viva la Edge Function hasta el timeout de la plataforma y el cliente
// no sabe si la invitacion llego a crearse. `504` significa "dependencia no
// respondio"; nunca se traduce como sesion invalida ni como reversion confirmada.
export function timeoutDesdeEntorno(valor: string | undefined): number {
  if (valor === undefined) return 10000;
  const numero = Number(valor);
  return Number.isSafeInteger(numero) && numero >= 50 && numero <= 60000
    ? numero
    : 10000;
}

export const TIMEOUT_MS = timeoutDesdeEntorno(Deno.env.get("AUTH_TIMEOUT_MS"));

export function puertoDesdeEntorno(valor: string | undefined): number {
  const puerto = Number(valor ?? "8000");
  return Number.isFinite(puerto) ? puerto : 8000;
}

export const PUERTO = puertoDesdeEntorno(Deno.env.get("PORT"));

export interface Configuracion {
  supabaseUrl: string;
  serviceRoleKey: string;
  anonKey: string;
  redirectTo: string;
}

export interface EntornoInvitacion {
  SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  SUPABASE_ANON_KEY?: string;
  APP_REDIRECT_URL?: string;
}

export function configuracionDesdeEntorno(
  entorno: EntornoInvitacion,
): Configuracion | null {
  const supabaseUrl = entorno.SUPABASE_URL;
  const serviceRoleKey = entorno.SUPABASE_SERVICE_ROLE_KEY;
  const anonKey = entorno.SUPABASE_ANON_KEY;
  if (!supabaseUrl || !serviceRoleKey || !anonKey) return null;
  return {
    supabaseUrl,
    serviceRoleKey,
    anonKey,
    redirectTo: entorno.APP_REDIRECT_URL ?? REDIRECT_POR_DEFECTO,
  };
}

export function leerConfiguracion(): Configuracion | null {
  return configuracionDesdeEntorno({
    SUPABASE_URL: Deno.env.get("SUPABASE_URL"),
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    SUPABASE_ANON_KEY: Deno.env.get("SUPABASE_ANON_KEY"),
    APP_REDIRECT_URL: Deno.env.get("APP_REDIRECT_URL"),
  });
}
