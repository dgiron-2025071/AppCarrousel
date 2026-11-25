// Capa HTTP: construccion de respuestas y traduccion de fallos no controlados.

import { esTimeout } from "./errores.ts";

export const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

export function error(mensaje: string, status = 400): Response {
  return json({ error: mensaje }, status);
}

export function respuestaFalloNoControlado(fallo: unknown): Response {
  if (esTimeout(fallo)) {
    return error(
      "Una dependencia no respondió a tiempo. Intenta de nuevo.",
      504,
    );
  }
  console.error("Error no controlado en invitar-usuario", fallo);
  return error("Error interno de la función.", 500);
}
