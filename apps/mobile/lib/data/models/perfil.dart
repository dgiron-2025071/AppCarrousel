class Perfil {
  const Perfil({
    required this.id,
    required this.empresaId,
    required this.centroCostoId,
    required this.rol,
    required this.nombreCompleto,
    this.centroNombre,
  });

  final String id;
  final String empresaId;
  final String centroCostoId;
  final String rol;
  final String nombreCompleto;
  final String? centroNombre;

  bool get esAdmin => rol == 'admin';

  String get primerNombre {
    final partes = nombreCompleto.trim().split(RegExp(r'\s+'));
    return partes.isEmpty ? nombreCompleto : partes.first;
  }

  String get rolEtiqueta => esAdmin ? 'Administrador' : 'Empleado';

  factory Perfil.fromMap(Map<String, dynamic> map) {
    String? centroNombre;
    final centro = map['centros_costo'];
    if (centro is Map<String, dynamic>) {
      centroNombre = centro['nombre'] as String?;
    }
    return Perfil(
      id: map['id'] as String,
      empresaId: map['empresa_id'] as String,
      centroCostoId: map['centro_costo_id'] as String,
      rol: map['rol'] as String,
      nombreCompleto: map['nombre_completo'] as String,
      centroNombre: centroNombre,
    );
  }
}
