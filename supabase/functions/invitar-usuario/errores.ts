// Capa de errores de dependencia: clasifica timeouts sin mezclarlos con
// sesiones invalidas ni con reversiones confirmadas.

import { TIMEOUT_MS } from "./config.ts";

export const MARCA_TIMEOUT = "carrousel_timeout_dependencia";

// `name`/`code` de aborto son necesarios: postgrest-js reintenta cualquier otro
// fallo de red con backoff, lo que convertiria un timeout corto en una espera
// de varios segundos. El mensaje conserva la marca para clasificar la respuesta.
export class TimeoutDependencia extends Error {
  override name = "AbortError";
  readonly code = "ABORT_ERR";

  constructor(causa: unknown) {
    super(MARCA_TIMEOUT, { cause: causa });
  }
}

export function esTimeout(valor: unknown): boolean {
  if (!valor) return false;
  if (valor instanceof TimeoutDependencia) return true;
  const mensaje = typeof valor === "string"
    ? valor
    : (valor as { message?: unknown } | null)?.message;
  return typeof mensaje === "string" && mensaje.includes(MARCA_TIMEOUT);
}

// Se inyecta en `createClient` a traves de `global.fetch`. La marca viaja en el
// mensaje porque supabase-js convierte las excepciones de fetch en objetos de
// error antes de devolverlos a la funcion.
export const fetchConTimeout: typeof fetch = async (entrada, init) => {
  const control = AbortSignal.timeout(TIMEOUT_MS);
  const señal = init?.signal
    ? AbortSignal.any([init.signal, control])
    : control;
  try {
    return await fetch(entrada, { ...init, signal: señal });
  } catch (error) {
    if (control.aborted) throw new TimeoutDependencia(error);
    throw error;
  }
};
