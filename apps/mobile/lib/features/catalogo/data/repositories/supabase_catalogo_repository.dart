import 'package:carrousel_app/features/catalogo/data/mappers/catalogo_mapper.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';
import 'package:carrousel_app/features/catalogo/domain/repositories/catalogo_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseCatalogoRepository implements CatalogoRepository {
  SupabaseCatalogoRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CentroCosto>> centros() async {
    final filas = await _client
        .from('centros_costo')
        .select('id, codigo, nombre, padre_id')
        .order('nombre');
    return filas.map(centroCostoDesdeMapa).toList(growable: false);
  }

  @override
  Future<List<Parque>> parques() async {
    final filas = await _client
        .from('parques')
        .select(
          'id, empresa_id, centro_costo_id, codigo, nombre, latitud, longitud, radio_metros, activo',
        )
        .order('nombre');
    return filas.map(parqueDesdeMapa).toList(growable: false);
  }

  @override
  Future<Map<String, String>> nombresDePerfiles() async {
    final filas = await _client.from('perfiles').select('id, nombre_completo');
    return {
      for (final fila in filas)
        fila['id'] as String: fila['nombre_completo'] as String,
    };
  }
}
