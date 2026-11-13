enum EstadoSolicitud {
  pendiente('Pendiente'),
  aprobada('Aprobada'),
  rechazada('Rechazada'),
  cancelada('Cancelada');

  const EstadoSolicitud(this.etiqueta);

  final String etiqueta;

  static EstadoSolicitud parse(String? valor) {
    for (final estado in values) {
      if (estado.name == valor) return estado;
    }
    return EstadoSolicitud.pendiente;
  }
}

/// Solicitud de horas extras de un especialista.
class SolicitudHorasExtras {
  const SolicitudHorasExtras({
    required this.id,
    required this.empresaId,
    required this.empleadoId,
    required this.centroCostoId,
    required this.inicio,
    required this.fin,
    required this.justificacion,
    required this.estado,
    required this.creadoEn,
    this.comentarioAdmin,
    this.revisadoPor,
    this.revisadoEn,
  });

  final String id;
  final String empresaId;
  final String empleadoId;
  final String centroCostoId;
  final DateTime inicio;
  final DateTime fin;
  final String justificacion;
  final EstadoSolicitud estado;
  final DateTime creadoEn;
  final String? comentarioAdmin;
  final String? revisadoPor;
  final DateTime? revisadoEn;

  Duration get duracion => fin.difference(inicio);
}

/// Solicitud enriquecida con los nombres que muestra la interfaz.
class SolicitudDetalle {
  const SolicitudDetalle({
    required this.solicitud,
    required this.empleadoNombre,
    required this.centroNombre,
  });

  final SolicitudHorasExtras solicitud;
  final String empleadoNombre;
  final String centroNombre;
}
