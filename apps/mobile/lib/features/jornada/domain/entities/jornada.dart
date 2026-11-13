import 'package:carrousel_app/core/utils/duraciones.dart';

/// Jornada de trabajo de un empleado.
class Jornada {
  const Jornada({
    required this.id,
    required this.empresaId,
    required this.empleadoId,
    required this.parqueId,
    required this.entradaEn,
    required this.entradaDentroGeocerca,
    this.salidaEn,
    this.salidaDentroGeocerca,
  });

  final String id;
  final String empresaId;
  final String empleadoId;
  final String parqueId;
  final DateTime entradaEn;
  final DateTime? salidaEn;
  final bool entradaDentroGeocerca;
  final bool? salidaDentroGeocerca;

  bool get abierta => salidaEn == null;

  Duration duracionHasta(DateTime ahora) =>
      (salidaEn ?? ahora).difference(entradaEn);

  String get rangoTexto {
    final inicio = formatearHora(entradaEn);
    final fin = salidaEn == null ? 'en curso' : formatearHora(salidaEn!);
    return '$inicio - $fin';
  }
}
