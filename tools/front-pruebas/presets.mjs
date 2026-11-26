// Catálogo de consultas y acciones del front de pruebas.
// No contiene credenciales ni URLs de un proyecto real: las rutas son relativas
// al SUPABASE_URL que la persona escribe en el navegador.

export const TOKENS = [
  "usuario",
  "empresa",
  "centro",
  "parque",
  "jornada",
  "solicitud",
  "registro",
  "puesto",
  "lat",
  "lon",
  "codigo_empresa",
];

export const CONSULTAS = [
  {
    id: "perfil",
    etiqueta: "Mi perfil",
    ruta: "/rest/v1/perfiles?id=eq.{{usuario}}&select=*",
    nota: "El perfil materializado desde app_metadata.",
  },
  {
    id: "empresas",
    etiqueta: "Empresas",
    ruta: "/rest/v1/empresas?select=*&order=codigo",
    nota: "RLS solo permite ver la empresa del JWT.",
  },
  {
    id: "centros",
    etiqueta: "Centros de costo",
    ruta: "/rest/v1/centros_costo?select=*&order=codigo",
    nota: "Jerarquía completa de la empresa.",
  },
  {
    id: "parques",
    etiqueta: "Parques",
    ruta: "/rest/v1/parques?select=*&order=codigo",
    nota: "Incluye latitud, longitud y radio de la geocerca.",
  },
  {
    id: "puestos",
    etiqueta: "Puestos",
    ruta: "/rest/v1/puestos?select=*&order=codigo",
    nota: "Catálogo de puestos de la empresa.",
  },
  {
    id: "horarios",
    etiqueta: "Horarios",
    ruta: "/rest/v1/horarios?select=*&order=dia_semana",
    nota: "Horario semanal por empleado.",
  },
  {
    id: "parques-centros",
    etiqueta: "CECOs por parque",
    ruta: "/rest/v1/parques_centros?select=*&limit=50",
    nota: "El CECO principal se sincroniza solo al crear el parque.",
  },
  {
    id: "jornadas",
    etiqueta: "Jornadas",
    ruta: "/rest/v1/jornadas?select=*&order=entrada_en.desc&limit=20",
    nota: "Marcajes propios o del subárbol si es admin.",
  },
  {
    id: "horas-extras",
    etiqueta: "Horas extras",
    ruta: "/rest/v1/solicitudes_horas_extras?select=*&order=creado_en.desc&limit=20",
    nota: "Solicitudes propias o del equipo.",
  },
  {
    id: "registros",
    etiqueta: "Registros por código",
    ruta: "/rest/v1/registros_pendientes?select=*&order=creado_en.desc&limit=20",
    nota: "El solicitante ve el suyo; el admin ve los de su empresa.",
  },
  {
    id: "incidencias",
    etiqueta: "Incidencias",
    ruta: "/rest/v1/incidencias_jornada?select=*&order=creado_en.desc&limit=20",
    nota: "Las calcula el backend al cerrar o ajustar la jornada.",
  },
  {
    id: "ajustes",
    etiqueta: "Historial de ajustes",
    ruta: "/rest/v1/jornadas_ajustes?select=*&order=creado_en.desc&limit=20",
    nota: "Historial inmutable de correcciones de jornada.",
  },
  {
    id: "reporte-horas",
    etiqueta: "Reporte de horas extras",
    ruta: "/rest/v1/reporte_horas_extras?select=*&order=creado_en.desc&limit=20",
    nota: "Vista con security_invoker: respeta la misma RLS.",
  },
  {
    id: "cumplimiento",
    etiqueta: "Cumplimiento de jornadas",
    ruta: "/rest/v1/cumplimiento_jornadas?select=*&order=entrada_en.desc&limit=20",
    nota: "Vista con horario programado, diferencias e incidencias.",
  },
];

export const ACCIONES = [
  {
    id: "invitar-empleado",
    etiqueta: "Invitar empleado",
    tipo: "funcion",
    metodo: "POST",
    ruta: "/functions/v1/invitar-usuario",
    nota: "Requiere sesión de admin. La empresa sale del JWT, no del cuerpo.",
    cuerpo: {
      email: "empleado@ejemplo.test",
      nombre_completo: "Empleado Ejemplo",
      rol: "empleado",
      centro_costo_id: "{{centro}}",
    },
  },
  {
    id: "invitar-admin",
    etiqueta: "Invitar admin",
    tipo: "funcion",
    metodo: "POST",
    ruta: "/functions/v1/invitar-usuario",
    nota: "Igual que la anterior, con rol admin y centro dentro del subárbol.",
    cuerpo: {
      email: "admin@ejemplo.test",
      nombre_completo: "Admin Ejemplo",
      rol: "admin",
      centro_costo_id: "{{centro}}",
    },
  },
  {
    id: "crear-centro",
    etiqueta: "Crear centro hijo",
    tipo: "rest",
    metodo: "POST",
    ruta: "/rest/v1/centros_costo",
    nota: "Solo admin; el padre debe estar en su alcance. Las raíces se crean por SQL.",
    cuerpo: {
      empresa_id: "{{empresa}}",
      padre_id: "{{centro}}",
      codigo: "HIJO-DEMO",
      nombre: "Centro hijo de prueba",
    },
  },
  {
    id: "crear-parque",
    etiqueta: "Crear parque",
    tipo: "rest",
    metodo: "POST",
    ruta: "/rest/v1/parques",
    nota: "La geocerca se valida en base de datos. Copia lat/long de un parque existente.",
    cuerpo: {
      empresa_id: "{{empresa}}",
      centro_costo_id: "{{centro}}",
      codigo: "PARQUE-DEMO",
      nombre: "Parque de prueba",
      direccion: "Dirección de prueba",
      latitud: "{{lat}}",
      longitud: "{{lon}}",
      radio_metros: 100,
      activo: true,
    },
  },
  {
    id: "crear-puesto",
    etiqueta: "Crear puesto",
    tipo: "rest",
    metodo: "POST",
    ruta: "/rest/v1/puestos",
    nota: "Solo admin; el catálogo es por empresa.",
    cuerpo: {
      empresa_id: "{{empresa}}",
      codigo: "ESP",
      nombre: "Especialista",
      descripcion: "Puesto creado desde el front de pruebas",
      activo: true,
    },
  },
  {
    id: "crear-horario",
    etiqueta: "Crear horario",
    tipo: "rest",
    metodo: "POST",
    ruta: "/rest/v1/horarios",
    nota: "Solo admin. Un dia_semana por empleado: 1 = lunes, 7 = domingo.",
    cuerpo: {
      empresa_id: "{{empresa}}",
      empleado_id: "{{usuario}}",
      dia_semana: 1,
      hora_entrada: "08:00:00",
      hora_salida: "17:00:00",
      tolerancia_entrada_min: 10,
      tolerancia_salida_min: 10,
      activo: true,
    },
  },
  {
    id: "abrir-jornada",
    etiqueta: "Abrir jornada",
    tipo: "rest",
    metodo: "POST",
    ruta: "/rest/v1/jornadas",
    nota: "Como empleado, con GPS dentro del parque. empresa_id y empleado_id salen del JWT.",
    cuerpo: {
      parque_id: "{{parque}}",
      entrada_lat: "{{lat}}",
      entrada_lon: "{{lon}}",
      entrada_precision_metros: 10,
    },
  },
  {
    id: "cerrar-jornada",
    etiqueta: "Cerrar jornada",
    tipo: "rest",
    metodo: "PATCH",
    ruta: "/rest/v1/jornadas?id=eq.{{jornada}}",
    nota: "Como empleado, sobre su propia jornada abierta. El trigger fija salida_en.",
    cuerpo: {
      salida_lat: "{{lat}}",
      salida_lon: "{{lon}}",
      salida_precision_metros: 10,
    },
  },
  {
    id: "crear-horas-extras",
    etiqueta: "Crear horas extras",
    tipo: "rest",
    metodo: "POST",
    ruta: "/rest/v1/solicitudes_horas_extras",
    nota: "Estado pendiente y revisor vacío los fija la base; ajusta inicio y fin.",
    cuerpo: {
      centro_costo_id: "{{centro}}",
      inicio: "2026-11-26T17:00:00Z",
      fin: "2026-11-26T19:00:00Z",
      justificacion: "Apoyo operativo de prueba desde el front",
    },
  },
  {
    id: "cancelar-horas-extras",
    etiqueta: "Cancelar horas extras",
    tipo: "rest",
    metodo: "PATCH",
    ruta: "/rest/v1/solicitudes_horas_extras?id=eq.{{solicitud}}",
    nota: "Solo el dueño puede cancelar su solicitud pendiente.",
    cuerpo: { estado: "cancelada" },
  },
  {
    id: "aprobar-horas-extras",
    etiqueta: "Aprobar horas extras",
    tipo: "rest",
    metodo: "PATCH",
    ruta: "/rest/v1/solicitudes_horas_extras?id=eq.{{solicitud}}",
    nota: "Solo admin, de un empleado de su subárbol; no puede revisar la propia.",
    cuerpo: {
      estado: "aprobada",
      comentario_admin: "Aprobada desde el front de pruebas",
    },
  },
  {
    id: "rechazar-horas-extras",
    etiqueta: "Rechazar horas extras",
    tipo: "rest",
    metodo: "PATCH",
    ruta: "/rest/v1/solicitudes_horas_extras?id=eq.{{solicitud}}",
    nota: "Solo admin, con las mismas reglas que la aprobación.",
    cuerpo: {
      estado: "rechazada",
      comentario_admin: "Rechazada desde el front de pruebas",
    },
  },
  {
    id: "solicitar-registro",
    etiqueta: "Solicitar alta por código",
    tipo: "rpc",
    metodo: "POST",
    ruta: "/rest/v1/rpc/solicitar_registro",
    nota: "Úsalo con un usuario recién registrado que todavía no tenga perfil.",
    cuerpo: {
      p_codigo_empresa: "{{codigo_empresa}}",
      p_nombre_completo: "Nueva Persona",
      p_puesto: "Especialista",
    },
  },
  {
    id: "aprobar-registro",
    etiqueta: "Aprobar alta por código",
    tipo: "rpc",
    metodo: "POST",
    ruta: "/rest/v1/rpc/aprobar_registro",
    nota: "Solo admin; escribe los claims con rol empleado y materializa el perfil.",
    cuerpo: {
      p_registro_id: "{{registro}}",
      p_centro_costo_id: "{{centro}}",
    },
  },
  {
    id: "rechazar-registro",
    etiqueta: "Rechazar alta por código",
    tipo: "rpc",
    metodo: "POST",
    ruta: "/rest/v1/rpc/rechazar_registro",
    nota: "Solo admin; el motivo es obligatorio.",
    cuerpo: {
      p_registro_id: "{{registro}}",
      p_motivo: "Datos incompletos en la solicitud de prueba",
    },
  },
  {
    id: "ajustar-jornada",
    etiqueta: "Ajustar jornada",
    tipo: "rpc",
    metodo: "POST",
    ruta: "/rest/v1/rpc/ajustar_jornada",
    nota: "Solo admin; la jornada debe estar cerrada y el motivo es obligatorio.",
    cuerpo: {
      p_jornada_id: "{{jornada}}",
      p_entrada_en: "2026-11-26T08:00:00Z",
      p_salida_en: "2026-11-26T17:00:00Z",
      p_motivo: "Corrección de horario desde el front de pruebas",
    },
  },
  {
    id: "crear-ceco-parque",
    etiqueta: "Añadir CECO a parque",
    tipo: "rest",
    metodo: "POST",
    ruta: "/rest/v1/parques_centros",
    nota: "CECO adicional; el principal lo crea y protege el backend.",
    cuerpo: {
      empresa_id: "{{empresa}}",
      parque_id: "{{parque}}",
      centro_costo_id: "{{centro}}",
      principal: false,
      activo: true,
    },
  },
];

// Reemplaza marcadores por valores del navegador. Un marcador sin valor se
// conserva para que la persona vea qué falta en lugar de enviar una cadena vacía.
export function interpolar(texto, contexto) {
  return String(texto).replace(/\{\{([a-z_]+)\}\}/g, (completo, clave) => {
    const valor = contexto?.[clave];
    return valor === undefined || valor === null || valor === "" ? completo : String(valor);
  });
}

function interpolarValor(valor, contexto) {
  if (typeof valor === "string") return interpolar(valor, contexto);
  if (Array.isArray(valor)) return valor.map((elemento) => interpolarValor(elemento, contexto));
  if (valor && typeof valor === "object") {
    return Object.fromEntries(
      Object.entries(valor).map(([clave, contenido]) => [clave, interpolarValor(contenido, contexto)]),
    );
  }
  return valor;
}

export function cuerpoAccion(accion, contexto = {}) {
  return JSON.stringify(interpolarValor(accion.cuerpo ?? {}, contexto), null, 2);
}

export function rutaAccion(accion, contexto = {}) {
  return interpolar(accion.ruta, contexto);
}
