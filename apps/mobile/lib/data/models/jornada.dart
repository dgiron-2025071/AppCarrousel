import '../../core/utils/duraciones.dart';

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

  factory Jornada.fromMap(Map<String, dynamic> map) => Jornada(
        id: map['id'] as String,
        empresaId: map['empresa_id'] as String,
        empleadoId: map['empleado_id'] as String,
        parqueId: map['parque_id'] as String,
        entradaEn: DateTime.parse(map['entrada_en'] as String).toLocal(),
        salidaEn: map['salida_en'] == null
            ? null
            : DateTime.parse(map['salida_en'] as String).toLocal(),
        entradaDentroGeocerca: map['entrada_dentro_geocerca'] as bool? ?? false,
        salidaDentroGeocerca: map['salida_dentro_geocerca'] as bool?,
      );
}
