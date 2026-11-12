class CentroCosto {
  const CentroCosto({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.padreId,
  });

  final String id;
  final String codigo;
  final String nombre;
  final String? padreId;

  /// "057.01 · Andaria Kiddies", como aparece en contabilidad.
  String get etiqueta => codigo.isEmpty ? nombre : '$codigo · $nombre';

  factory CentroCosto.fromMap(Map<String, dynamic> map) => CentroCosto(
        id: map['id'] as String,
        codigo: map['codigo'] as String? ?? '',
        nombre: map['nombre'] as String,
        padreId: map['padre_id'] as String?,
      );
}
