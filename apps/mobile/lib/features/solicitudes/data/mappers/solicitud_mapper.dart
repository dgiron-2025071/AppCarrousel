import 'package:carrousel_app/features/solicitudes/domain/entities/solicitud_horas_extras.dart';

SolicitudHorasExtras solicitudDesdeMapa(Map<String, dynamic> map) =>
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
