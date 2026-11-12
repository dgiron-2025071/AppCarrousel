import 'solicitud_horas_extras.dart';

/// Fila de la vista `reporte_horas_extras`: las columnas del formulario
/// "Formato de horas Extras" más el estado de la aprobación.
class FilaReporteHorasExtras {
  const FilaReporteHorasExtras({
    required this.id,
    required this.empleado,
    required this.inicio,
    required this.fin,
    required this.horas,
    required this.actividadRealizada,
    required this.cecoCodigo,
    required this.cecoNombre,
    required this.estado,
    required this.creadoEn,
    this.puesto,
    this.personaQueAutoriza,
    this.revisadoPor,
    this.revisadoEn,
    this.comentarioAdmin,
  });

  final String id;
  final String empleado;
  final String? puesto;
  final DateTime inicio;
  final DateTime fin;
  final double horas;
  final String actividadRealizada;
  final String cecoCodigo;
  final String cecoNombre;
  final String? personaQueAutoriza;
  final EstadoSolicitud estado;
  final String? revisadoPor;
  final DateTime? revisadoEn;
  final String? comentarioAdmin;
  final DateTime creadoEn;

  static DateTime? _fecha(Object? valor) =>
      valor == null ? null : DateTime.parse(valor as String).toLocal();

  factory FilaReporteHorasExtras.fromMap(Map<String, dynamic> map) =>
      FilaReporteHorasExtras(
        id: map['id'] as String,
        empleado: map['empleado'] as String,
        puesto: map['puesto'] as String?,
        inicio: _fecha(map['inicio'])!,
        fin: _fecha(map['fin'])!,
        // PostgREST entrega numeric como número o texto según la versión.
        horas: double.parse('${map['horas']}'),
        actividadRealizada: map['actividad_realizada'] as String,
        cecoCodigo: map['ceco_codigo'] as String? ?? '',
        cecoNombre: map['ceco_nombre'] as String,
        personaQueAutoriza: map['persona_que_autoriza'] as String?,
        estado: EstadoSolicitud.parse(map['estado'] as String?),
        revisadoPor: map['revisado_por'] as String?,
        revisadoEn: _fecha(map['revisado_en']),
        comentarioAdmin: map['comentario_admin'] as String?,
        creadoEn: _fecha(map['creado_en'])!,
      );
}
