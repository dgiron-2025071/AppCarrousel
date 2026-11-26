// Front de pruebas de Carrousel: HTML + JavaScript del navegador, sin frameworks.
// La configuración y los tokens viven solo en memoria: nada se guarda en el
// almacenamiento persistente del navegador ni en cookies.

import {
  ACCIONES,
  CONSULTAS,
  TOKENS,
  cuerpoAccion,
  interpolar,
  rutaAccion,
} from "./presets.mjs";

const $ = (id) => document.getElementById(id);

const ETIQUETAS_ID = {
  usuario: "Usuario (auth.uid)",
  empresa: "Empresa de prueba",
  centro: "Centro de prueba",
  parque: "Parque de prueba",
  jornada: "Jornada de prueba",
  solicitud: "Solicitud de horas extras",
  registro: "Registro por código",
  puesto: "Puesto de prueba",
  lat: "Latitud de prueba",
  lon: "Longitud de prueba",
  codigo_empresa: "Código de empresa",
};

const estado = { tokens: null, claims: null, usuarioAuth: null };

function hora() {
  return new Date().toLocaleTimeString("es-GB", { hour12: false });
}

function log(titulo, detalle = "") {
  const destino = $("log");
  const linea = `[${hora()}] ${titulo}${detalle ? `\n${detalle}` : ""}`;
  destino.textContent = destino.textContent
    ? `${destino.textContent}\n\n${linea}`
    : linea;
  destino.scrollTop = destino.scrollHeight;
}

function conManejo(fn) {
  return async () => {
    try {
      await fn();
    } catch (error) {
      log("ERROR", error instanceof Error ? error.message : String(error));
    }
  };
}

function leerConfiguracion() {
  const url = $("url").value.trim().replace(/\/+$/, "");
  if (!/^https?:\/\//i.test(url)) {
    throw new Error("Escribe la URL de Supabase, por ejemplo https://<proyecto>.supabase.co");
  }
  // new URL valida que no haya espacios ni caracteres raros en el host.
  new URL(url);

  const anon = $("anon").value.trim();
  if (!anon) throw new Error("Pega la anon key de Supabase (no la clave de servicio)");

  const funcion = $("funcion").value.trim().replace(/\/+$/, "") ||
    `${url}/functions/v1/invitar-usuario`;

  return { url, anon, funcion };
}

function tokenActual() {
  return estado.tokens?.access_token ?? "";
}

function decodificarJwt(token) {
  const parte = token.split(".")[1];
  if (!parte) throw new Error("El token no tiene forma de JWT");
  const normalizada = parte.replace(/-/g, "+").replace(/_/g, "/");
  const relleno = normalizada.length % 4 === 0 ? "" : "=".repeat(4 - normalizada.length % 4);
  const binario = atob(normalizada + relleno);
  const bytes = Uint8Array.from(binario, (caracter) => caracter.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}

function fechaLegible(epoch) {
  return typeof epoch === "number" ? new Date(epoch * 1000).toISOString() : "—";
}

function renderSesion() {
  const claims = estado.claims ?? {};
  const app = claims.app_metadata ?? {};
  const appAuth = estado.usuarioAuth?.app_metadata ?? {};
  const texto = [
    `Autenticado: ${tokenActual() ? "sí" : "no"}`,
    `Usuario: ${claims.sub ?? "—"}`,
    `Correo del token: ${claims.email ?? "—"}`,
    `Rol (app_metadata): ${app.rol ?? "—"}`,
    `Empresa (app_metadata): ${app.empresa_id ?? "—"}`,
    `Centro (app_metadata): ${app.centro_costo_id ?? "—"}`,
    `Expira: ${fechaLegible(claims.exp)}`,
    "",
    "app_metadata del JWT:",
    JSON.stringify(app, null, 2),
    "",
    "app_metadata actual de Auth (/auth/v1/user):",
    JSON.stringify(appAuth, null, 2),
  ].join("\n");
  $("session").textContent = texto;
}

function contexto() {
  const claims = estado.claims ?? {};
  const app = claims.app_metadata ?? {};
  const valores = {
    usuario: claims.sub ?? "",
    empresa: app.empresa_id ?? "",
    centro: app.centro_costo_id ?? "",
    parque: "",
    jornada: "",
    solicitud: "",
    registro: "",
    puesto: "",
    lat: "",
    lon: "",
    codigo_empresa: "",
  };
  for (const clave of TOKENS) {
    const campo = $(`v-${clave}`);
    const valor = campo?.value.trim();
    if (valor) valores[clave] = valor;
  }
  return valores;
}

async function peticion({
  url,
  ruta = "",
  metodo = "GET",
  cuerpo,
  urlBase,
  autenticada = true,
  prefer = true,
  redactar = false,
}) {
  const cfg = leerConfiguracion();
  const destino = url ?? `${urlBase ?? cfg.url}${ruta}`;
  const cabeceras = {
    apikey: cfg.anon,
    Accept: "application/json",
  };

  if (autenticada) {
    const token = tokenActual();
    if (!token) throw new Error("Inicia sesión primero (o pega un access token)");
    cabeceras.Authorization = `Bearer ${token}`;
  }

  let cuerpoTexto;
  if (cuerpo !== undefined && metodo !== "GET") {
    cabeceras["Content-Type"] = "application/json";
    cuerpoTexto = typeof cuerpo === "string" ? cuerpo : JSON.stringify(cuerpo);
    log("Cuerpo", redactar ? "[redactado]" : cuerpoTexto);
  }

  if (prefer && ["POST", "PATCH", "PUT", "DELETE"].includes(metodo)) {
    cabeceras.Prefer = "return=representation";
  }

  log("Petición", `${metodo} ${destino}`);
  const respuesta = await fetch(destino, {
    method: metodo,
    headers: cabeceras,
    body: cuerpoTexto,
  });
  const texto = await respuesta.text();
  let datos = texto;
  try {
    datos = texto ? JSON.parse(texto) : null;
  } catch {
    // PostgREST y GoTrue pueden responder texto plano; se muestra tal cual.
  }

  if (!respuesta.ok) {
    const detalle = typeof datos === "string" ? datos : JSON.stringify(datos);
    log("Respuesta", `${respuesta.status} ${detalle}`);
    throw new Error(`${respuesta.status}: ${detalle}`);
  }

  log("Respuesta", `${respuesta.status} ${redactar ? "[redactado]" : (texto || "(vacía)")}`);
  return datos;
}

function guardarSesion(datos) {
  if (!datos?.access_token) {
    throw new Error("La respuesta de Auth no trae access_token");
  }
  estado.tokens = {
    access_token: datos.access_token,
    refresh_token: datos.refresh_token ?? "",
  };
  estado.claims = decodificarJwt(datos.access_token);
  estado.usuarioAuth = datos.user ?? null;
  renderSesion();
  const rol = estado.claims.app_metadata?.rol ?? "sin rol";
  log("Sesión iniciada", `Usuario ${estado.claims.sub ?? "—"} · rol ${rol} (token no mostrado)`);
}

function construirCamposId() {
  const contenedor = $("campos-id");
  for (const clave of TOKENS) {
    const etiqueta = document.createElement("label");
    etiqueta.textContent = ETIQUETAS_ID[clave] ?? clave;

    const campo = document.createElement("input");
    campo.id = `v-${clave}`;
    campo.type = "text";
    campo.autocomplete = "off";
    campo.placeholder = clave === "codigo_empresa" ? "DEMO" : "pegar valor de prueba";
    campo.addEventListener("input", () => {
      if (accionSeleccionada()) $("accion-ruta").textContent =
        `${accionSeleccionada().metodo} ${rutaAccion(accionSeleccionada(), contexto())}`;
    });

    etiqueta.appendChild(campo);
    contenedor.appendChild(etiqueta);
  }
}

function construirConsultas() {
  const contenedor = $("consultas-botones");
  for (const consulta of CONSULTAS) {
    const boton = document.createElement("button");
    boton.type = "button";
    boton.textContent = consulta.etiqueta;
    boton.title = consulta.nota;
    boton.addEventListener("click", conManejo(async () => {
      const ruta = interpolar(consulta.ruta, contexto());
      await peticion({ ruta, metodo: "GET", prefer: false });
    }));
    contenedor.appendChild(boton);
  }
}

function accionSeleccionada() {
  return ACCIONES.find((accion) => accion.id === $("accion-select").value) ?? null;
}

function construirAcciones() {
  const selector = $("accion-select");
  for (const accion of ACCIONES) {
    const opcion = document.createElement("option");
    opcion.value = accion.id;
    opcion.textContent = accion.etiqueta;
    selector.appendChild(opcion);
  }
  selector.addEventListener("change", rellenarAccion);
  $("accion-rellenar").addEventListener("click", rellenarAccion);
  $("accion-ejecutar").addEventListener("click", conManejo(async () => {
    const accion = accionSeleccionada();
    if (!accion) throw new Error("Selecciona una acción");

    const texto = $("accion-cuerpo").value.trim();
    let cuerpo = {};
    if (texto) {
      try {
        cuerpo = JSON.parse(interpolar(texto, contexto()));
      } catch (error) {
        throw new Error(`JSON inválido: ${error.message}`);
      }
    }

    const cfg = leerConfiguracion();
    const url = accion.tipo === "funcion"
      ? cfg.funcion
      : undefined;
    const ruta = accion.tipo === "funcion"
      ? ""
      : rutaAccion(accion, contexto());

    await peticion({
      url,
      ruta,
      metodo: accion.metodo,
      cuerpo,
      prefer: accion.tipo !== "funcion",
    });
  }));
  rellenarAccion();
}

function rellenarAccion() {
  const accion = accionSeleccionada();
  if (!accion) return;
  const ctx = contexto();
  $("accion-nota").textContent = accion.nota;
  $("accion-ruta").textContent = `${accion.metodo} ${
    accion.tipo === "funcion" ? "URL de la Edge Function" : rutaAccion(accion, ctx)
  }`;
  $("accion-cuerpo").value = cuerpoAccion(accion, ctx);
}

function instalarEventos() {
  $("guardar-config").addEventListener("click", conManejo(async () => {
    leerConfiguracion();
    log("Configuración", "URL, anon key y función leídas; no se guardan en el navegador");
  }));

  $("limpiar-config").addEventListener("click", () => {
    for (const id of ["url", "anon", "funcion", "email", "password", "token-manual"]) {
      $(id).value = "";
    }
    for (const clave of TOKENS) $(`v-${clave}`).value = "";
    estado.tokens = null;
    estado.claims = null;
    estado.usuarioAuth = null;
    renderSesion();
    log("Configuración", "Valores y sesión borrados de memoria");
  });

  $("login").addEventListener("click", conManejo(async () => {
    const cfg = leerConfiguracion();
    const datos = await peticion({
      url: `${cfg.url}/auth/v1/token?grant_type=password`,
      metodo: "POST",
      cuerpo: { email: $("email").value.trim(), password: $("password").value },
      autenticada: false,
      prefer: false,
      redactar: true,
    });
    guardarSesion(datos);
  }));

  $("signup").addEventListener("click", conManejo(async () => {
    const cfg = leerConfiguracion();
    await peticion({
      url: `${cfg.url}/auth/v1/signup`,
      metodo: "POST",
      cuerpo: { email: $("email").value.trim(), password: $("password").value },
      autenticada: false,
      prefer: false,
      redactar: true,
    });
    log("Registro", "Revisa el correo si la confirmación de email está activada");
  }));

  $("ver-sesion").addEventListener("click", conManejo(async () => {
    if (!tokenActual()) throw new Error("No hay sesión en memoria");
    estado.claims = decodificarJwt(tokenActual());
    estado.usuarioAuth = await peticion({
      ruta: "/auth/v1/user",
      prefer: false,
    });
    renderSesion();
    log("Sesión", "Claims del JWT y de Auth actualizados en pantalla");
  }));

  $("logout").addEventListener("click", conManejo(async () => {
    try {
      const cfg = leerConfiguracion();
      await peticion({
        url: `${cfg.url}/auth/v1/logout`,
        metodo: "POST",
        autenticada: true,
        prefer: false,
        redactar: true,
      });
    } catch (error) {
      log("Aviso", `No se pudo invalidar en Auth, pero la sesión local se borra: ${error.message}`);
    } finally {
      estado.tokens = null;
      estado.claims = null;
      estado.usuarioAuth = null;
      $("password").value = "";
      renderSesion();
      log("Sesión", "Cerrada en este navegador");
    }
  }));

  $("usar-token").addEventListener("click", conManejo(async () => {
    const token = $("token-manual").value.trim();
    if (!token) throw new Error("Pega un access token antes de continuar");
    guardarSesion({ access_token: token });
    $("token-manual").value = "";
  }));

  $("generico-ejecutar").addEventListener("click", conManejo(async () => {
    const metodo = $("metodo").value;
    const ruta = interpolar($("ruta").value.trim(), contexto());
    if (!ruta) throw new Error("Escribe una ruta, por ejemplo /rest/v1/jornadas?select=*");
    const texto = $("cuerpo").value.trim();
    let cuerpo;
    if (texto) {
      try {
        cuerpo = JSON.parse(interpolar(texto, contexto()));
      } catch (error) {
        throw new Error(`JSON inválido: ${error.message}`);
      }
    }
    await peticion({ ruta, metodo, cuerpo });
  }));

  $("limpiar-log").addEventListener("click", () => {
    $("log").textContent = "";
  });
}

function leerTokenDeUrl() {
  const parte = window.location.hash.replace(/^#/, "") || window.location.search.replace(/^\?/, "");
  if (!parte) return;
  const parametros = new URLSearchParams(parte);
  const token = parametros.get("access_token");
  if (token) {
    guardarSesion({
      access_token: token,
      refresh_token: parametros.get("refresh_token") ?? "",
    });
    log("Invitación", "Se tomó el access token del enlace; no se muestra en el log");
    window.history.replaceState(null, "", window.location.pathname);
    return;
  }
  if (parametros.get("code")) {
    log("Aviso", "El enlace llegó con ?code=... (PKCE). Este front no canjea códigos: usa un enlace con token o pega el access token");
  }
}

construirCamposId();
construirConsultas();
construirAcciones();
instalarEventos();
renderSesion();
leerTokenDeUrl();
log("Listo", "Configura Supabase, inicia sesión y usa los botones. Nada se guarda en el navegador.");
