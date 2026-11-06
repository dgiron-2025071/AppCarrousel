enum EstadoSolicitud {
  pendiente('Pendiente'),
  aprobada('Aprobada'),
  rechazada('Rechazada');

  const EstadoSolicitud(this.etiqueta);

  final String etiqueta;

  static EstadoSolicitud parse(String? valor) {
    for (final estado in values) {
      if (estado.name == valor) return estado;
    }
    return EstadoSolicitud.pendiente;
  }
}

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

  factory SolicitudHorasExtras.fromMap(Map<String, dynamic> map) =>
      SolicitudHorasExtras(
        id: map['id'] as String,
        empresaId: map['empresa_id'] as String,
        empleadoId: map['empleado_id'] as String,
        centroCostoId: map['centro_costo_id'] as String,
        inicio: DateTime.parse(map['inicio'] as String).toLocal(),
        fin: DateTime.parse(map['fin'] as String).toLocal(),
        justificacion: map['justificacion'] as String,
        estado: EstadoSolicitud.parse(map['estado'] as String?),
        creadoEn: DateTime.parse(map['creado_en'] as String).toLocal(),
        comentarioAdmin: map['comentario_admin'] as String?,
        revisadoPor: map['revisado_por'] as String?,
        revisadoEn: map['revisado_en'] == null
            ? null
            : DateTime.parse(map['revisado_en'] as String).toLocal(),
      );
}

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
