/// Nodo de la jerarquía dinámica de centros de costo.
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
}
