DateTime? _fecha(Object? valor) =>
    valor == null ? null : DateTime.parse(valor as String).toLocal();

/// Solicitud de registro propio (tabla `registros`).
class Registro {
  const Registro({
    required this.id,
    required this.email,
    required this.nombre,
    required this.estado,
    required this.creadoEn,
    this.telefono,
    this.motivo,
  });

  final String id;
  final String email;
  final String nombre;
  final String? telefono;
  final String estado;
  final String? motivo;
  final DateTime creadoEn;

  bool get pendiente => estado == 'pendiente';
  bool get rechazado => estado == 'rechazado';

  factory Registro.fromMap(Map<String, dynamic> map) => Registro(
        id: map['id'] as String,
        email: map['email'] as String,
        nombre: map['nombre'] as String,
        telefono: map['telefono'] as String?,
        estado: map['estado'] as String,
        motivo: map['motivo'] as String?,
        creadoEn: _fecha(map['creado_en'])!,
      );
}

enum TipoIncidencia {
  llegadaTarde('llegada_tarde', 'Llegada tarde'),
  salidaTemprana('salida_temprana', 'Salida temprana'),
  parqueDistinto('parque_distinto', 'Parque distinto'),
  precisionBaja('precision_baja', 'GPS impreciso');

  const TipoIncidencia(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static TipoIncidencia parse(String valor) =>
      values.firstWhere((t) => t.valor == valor, orElse: () => llegadaTarde);
}

class Incidencia {
  const Incidencia({
    required this.id,
    required this.jornadaId,
    required this.empleadoId,
    required this.tipo,
    required this.severidad,
    required this.descripcion,
    required this.estado,
    required this.creadoEn,
    this.resolucion,
    this.resueltoEn,
  });

  final String id;
  final String jornadaId;
  final String empleadoId;
  final TipoIncidencia tipo;
  final String severidad;
  final String descripcion;
  final String estado;
  final String? resolucion;
  final DateTime creadoEn;
  final DateTime? resueltoEn;

  bool get abierta => estado == 'abierta';

  factory Incidencia.fromMap(Map<String, dynamic> map) => Incidencia(
        id: map['id'] as String,
        jornadaId: map['jornada_id'] as String,
        empleadoId: map['empleado_id'] as String,
        tipo: TipoIncidencia.parse(map['tipo'] as String),
        severidad: map['severidad'] as String,
        descripcion: map['descripcion'] as String,
        estado: map['estado'] as String,
        resolucion: map['resolucion'] as String?,
        creadoEn: _fecha(map['creado_en'])!,
        resueltoEn: _fecha(map['resuelto_en']),
      );
}

/// Indicadores del panel de administración.
class ResumenAdmin {
  const ResumenAdmin({
    required this.enTurno,
    required this.incidenciasAbiertas,
    required this.solicitudesPendientes,
    required this.registrosPendientes,
  });

  final int enTurno;
  final int incidenciasAbiertas;
  final int solicitudesPendientes;
  final int registrosPendientes;
}
