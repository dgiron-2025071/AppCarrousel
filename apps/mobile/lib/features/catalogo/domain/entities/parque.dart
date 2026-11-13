/// Lugar operativo con geocerca donde se marca la jornada.
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
}
