import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';

CentroCosto centroCostoDesdeMapa(Map<String, dynamic> map) => CentroCosto(
      id: map['id'] as String,
      codigo: map['codigo'] as String? ?? '',
      nombre: map['nombre'] as String,
      padreId: map['padre_id'] as String?,
    );

Parque parqueDesdeMapa(Map<String, dynamic> map) => Parque(
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
