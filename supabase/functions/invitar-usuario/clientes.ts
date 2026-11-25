// Capa de acceso a Supabase: construye los clientes con el timeout inyectado.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { fetchConTimeout } from "./errores.ts";

export type ClienteSupabase = SupabaseClient;

export function clienteSolicitante(
  supabaseUrl: string,
  anonKey: string,
  autorizacion: string,
): ClienteSupabase {
  return createClient(supabaseUrl, anonKey, {
    global: {
      headers: { Authorization: autorizacion },
      fetch: fetchConTimeout,
    },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function clienteAdmin(
  supabaseUrl: string,
  serviceRoleKey: string,
): ClienteSupabase {
  return createClient(supabaseUrl, serviceRoleKey, {
    global: { fetch: fetchConTimeout },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
