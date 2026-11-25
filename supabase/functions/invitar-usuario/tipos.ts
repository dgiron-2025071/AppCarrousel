// Contratos compartidos entre las capas de la Edge Function.

export interface InvitarBody {
  email?: unknown;
  nombre_completo?: unknown;
  rol?: unknown;
  centro_costo_id?: unknown;
}

export interface DatosInvitacion {
  email: string;
  nombre: string;
  rol: "empleado" | "admin";
  centroId: string;
}

export interface PerfilSolicitante {
  empresa_id: string;
  centro_costo_id: string;
  rol: string;
  activo: boolean;
}

export interface CentroDestino {
  id: string;
  empresa_id: string;
  ruta: string[] | null;
}

export interface EmpresaSolicitante {
  activa: boolean;
}

export interface ContextoAutorizado {
  perfil: PerfilSolicitante;
  centro: CentroDestino;
}
