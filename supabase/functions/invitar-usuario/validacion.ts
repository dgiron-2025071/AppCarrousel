// Capa de validacion de entrada y de claims del token.

import type { DatosInvitacion, InvitarBody } from "./tipos.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizarEmail(valor: unknown): string {
  if (typeof valor !== "string") return "";
  // NFC evita que dos representaciones Unicode del mismo correo creen cuentas
  // distintas.
  return valor.trim().normalize("NFC").toLowerCase().normalize("NFC");
}

// Los caracteres de control (C0 y DEL) no son validos en un correo y pueden
// confundir a GoTrue o a los logs. Se comprueban aparte para no esconderlos en
// una expresion regular.
export function tieneCaracterDeControl(valor: string): boolean {
  for (const caracter of valor) {
    const codigo = caracter.charCodeAt(0);
    if (codigo <= 0x1f || codigo === 0x7f) return true;
  }
  return false;
}

// Lee el payload del access token. La firma ya la validó la plataforma
// (`verify_jwt`) y `auth.getUser()` confirma que la sesión sigue vigente, así
// que aquí solo se decodifica para comparar los claims *emitidos*. No se usa
// `authData.user.app_metadata` porque ese campo refleja el registro actual del
// usuario, no el token: un admin movido de centro conservaría el alcance nuevo
// con un JWT viejo.
export function claimsDelToken(
  authorization: string,
): Record<string, unknown> | null {
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  const partes = token.split(".");
  if (partes.length !== 3) return null;

  try {
    const base64 = partes[1].replace(/-/g, "+").replace(/_/g, "/");
    const relleno = "=".repeat((4 - (base64.length % 4)) % 4);
    const payload = JSON.parse(atob(base64 + relleno));
    return payload && typeof payload === "object"
      ? payload as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

export type ResultadoValidacion =
  | { datos: DatosInvitacion; mensaje: null }
  | { datos: null; mensaje: string };

export function validarCuerpo(cuerpo: InvitarBody): ResultadoValidacion {
  const email = normalizarEmail(cuerpo.email);
  const nombre = typeof cuerpo.nombre_completo === "string"
    ? cuerpo.nombre_completo.trim()
    : "";
  const rol = typeof cuerpo.rol === "string" ? cuerpo.rol.trim() : "";
  const centroId = typeof cuerpo.centro_costo_id === "string"
    ? cuerpo.centro_costo_id.trim()
    : "";

  if (
    !EMAIL.test(email) || email.length > 320 || tieneCaracterDeControl(email)
  ) {
    return { datos: null, mensaje: "Escribe un correo electrónico válido." };
  }
  if (nombre.length < 2 || nombre.length > 120) {
    return {
      datos: null,
      mensaje: "El nombre completo debe tener entre 2 y 120 caracteres.",
    };
  }
  if (rol !== "empleado" && rol !== "admin") {
    return { datos: null, mensaje: "El rol debe ser empleado o admin." };
  }
  if (!UUID.test(centroId)) {
    return { datos: null, mensaje: "El centro de costo no es válido." };
  }

  return { datos: { email, nombre, rol, centroId }, mensaje: null };
}
