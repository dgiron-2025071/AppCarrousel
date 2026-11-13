import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';

Jornada jornadaDesdeMapa(Map<String, dynamic> map) => Jornada(
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
