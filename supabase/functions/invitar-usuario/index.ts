// =============================================================================
// Carrousel — Edge Function: invitación de usuarios
//
// Crea un usuario en Supabase Auth con una invitación por correo y escribe en
// `app_metadata` el alcance y el rol. El trigger de `public.perfiles`
// materializa el perfil; el cliente nunca puede escribir esos claims.
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
//
// Despliegue:
//   supabase functions deploy invitar-usuario
//   supabase secrets set APP_REDIRECT_URL=io.supabase.carrousel://login-callback
// =============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface InvitarBody {
  email?: unknown;
  nombre_completo?: unknown;
  rol?: unknown;
  centro_costo_id?: unknown;
}

interface PerfilSolicitante {
  empresa_id: string;
  centro_costo_id: string;
  rol: string;
  activo: boolean;
}

interface CentroDestino {
  id: string;
  empresa_id: string;
  ruta: string[] | null;
}

interface EmpresaSolicitante {
  activa: boolean;
}

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function error(mensaje: string, status = 400): Response {
  return json({ error: mensaje }, status);
}

const PORT = Number(Deno.env.get("PORT") ?? "8000");

Deno.serve(
  { port: Number.isFinite(PORT) ? PORT : 8000 },
  async (req: Request) => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: CORS });
    }
    if (req.method !== "POST") {
      return error("Método no permitido.", 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const redirectTo = Deno.env.get("APP_REDIRECT_URL") ??
      "io.supabase.carrousel://login-callback";

    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      return error("La función no está configurada correctamente.", 500);
    }

    const autorizacion = req.headers.get("Authorization");
    if (!autorizacion) {
      return error("Falta la sesión del administrador.", 401);
    }

    const clienteSolicitante = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: autorizacion } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await clienteSolicitante.auth
      .getUser();
    if (authError || !authData.user) {
      return error("Sesión inválida o expirada.", 401);
    }

    let cuerpo: InvitarBody;
    try {
      cuerpo = await req.json();
    } catch {
      return error("El cuerpo debe ser JSON válido.");
    }

    const email = typeof cuerpo.email === "string"
      ? cuerpo.email.trim().toLowerCase()
      : "";
    const nombre = typeof cuerpo.nombre_completo === "string"
      ? cuerpo.nombre_completo.trim()
      : "";
    const rol = typeof cuerpo.rol === "string" ? cuerpo.rol : "";
    const centroId = typeof cuerpo.centro_costo_id === "string"
      ? cuerpo.centro_costo_id
      : "";

    if (!EMAIL.test(email) || email.length > 320) {
      return error("Escribe un correo electrónico válido.");
    }
    if (nombre.length < 2 || nombre.length > 120) {
      return error("El nombre completo debe tener entre 2 y 120 caracteres.");
    }
    if (rol !== "empleado" && rol !== "admin") {
      return error("El rol debe ser empleado o admin.");
    }
    if (!UUID.test(centroId)) {
      return error("El centro de costo no es válido.");
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: perfiles, error: perfilError } = await admin
      .from("perfiles")
      .select("empresa_id, centro_costo_id, rol, activo")
      .eq("id", authData.user.id)
      .limit(1);

    if (perfilError) {
      return error("No se pudo verificar el perfil del solicitante.", 500);
    }
    const perfil = (perfiles?.[0] ?? null) as PerfilSolicitante | null;
    if (!perfil || perfil.rol !== "admin" || !perfil.activo) {
      return error("Solo un administrador activo puede invitar usuarios.", 403);
    }

    // El alcance autorizado es el del JWT (`app_metadata`), igual que en la base
    // de datos (`0017`). Si el perfil fue degradado o movido sin refrescar la
    // sesión, la función falla cerrada en lugar de ampliar el alcance.
    const claims = (authData.user.app_metadata ?? {}) as Record<
      string,
      unknown
    >;
    if (
      claims.rol !== "admin" ||
      claims.empresa_id !== perfil.empresa_id ||
      claims.centro_costo_id !== perfil.centro_costo_id
    ) {
      return error(
        "Tu sesión ya no refleja tu alcance actual. Vuelve a iniciar sesión.",
        403,
      );
    }

    // `service_role` ignora RLS: la suspensión de la empresa (0013) no basta.
    const { data: empresas, error: empresaError } = await admin
      .from("empresas")
      .select("activa")
      .eq("id", perfil.empresa_id)
      .limit(1);

    if (empresaError) {
      return error("No se pudo verificar la empresa.", 500);
    }
    const empresa = (empresas?.[0] ?? null) as EmpresaSolicitante | null;
    if (!empresa?.activa) {
      return error("La empresa está suspendida.", 403);
    }

    const { data: centros, error: centroError } = await admin
      .from("centros_costo")
      .select("id, empresa_id, ruta")
      .eq("id", centroId)
      .limit(1);

    if (centroError) {
      return error("No se pudo verificar el centro de costo.", 500);
    }
    const centro = (centros?.[0] ?? null) as CentroDestino | null;
    if (!centro || centro.empresa_id !== perfil.empresa_id) {
      return error("El centro de costo no pertenece a tu empresa.", 400);
    }

    const ruta = centro.ruta ?? [];
    const enAlcance = centro.id === perfil.centro_costo_id ||
      ruta.includes(perfil.centro_costo_id);
    if (!enAlcance) {
      return error(
        "Solo puedes invitar usuarios a centros dentro de tu subárbol.",
        403,
      );
    }

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
      // Rollback: no se deja un usuario de Auth sin perfil ni alcance.
      await admin.auth.admin.deleteUser(invitacion.user.id);
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
  },
);
