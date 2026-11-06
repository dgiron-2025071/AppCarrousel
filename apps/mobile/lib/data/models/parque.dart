class Parque {
  const Parque({
    required this.id,
    required this.empresaId,
    required this.centroCostoId,
    required this.codigo,
    required this.nombre,
    required this.latitud,
    required this.longitud,
    required this.radioMetros,
    required this.activo,
  });

  final String id;
  final String empresaId;
  final String centroCostoId;
  final String codigo;
  final String nombre;
  final double latitud;
  final double longitud;
  final double radioMetros;
  final bool activo;

  factory Parque.fromMap(Map<String, dynamic> map) => Parque(
        id: map['id'] as String,
        empresaId: map['empresa_id'] as String,
        centroCostoId: map['centro_costo_id'] as String,
        codigo: map['codigo'] as String? ?? '',
        nombre: map['nombre'] as String,
        latitud: (map['latitud'] as num).toDouble(),
        longitud: (map['longitud'] as num).toDouble(),
        radioMetros: (map['radio_metros'] as num).toDouble(),
        activo: map['activo'] as bool? ?? true,
      );
}
