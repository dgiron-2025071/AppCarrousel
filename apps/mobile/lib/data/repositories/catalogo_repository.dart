import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/centro_costo.dart';
import '../models/parque.dart';

class CatalogoRepository {
  CatalogoRepository(this._client);

  final SupabaseClient _client;

  Future<List<CentroCosto>> centros() async {
    final filas = await _client
        .from('centros_costo')
        .select('id, codigo, nombre, padre_id')
        .order('nombre');
    return filas.map(CentroCosto.fromMap).toList(growable: false);
  }

  Future<List<Parque>> parques() async {
    final filas = await _client
        .from('parques')
        .select(
          'id, empresa_id, centro_costo_id, codigo, nombre, latitud, longitud, radio_metros, activo',
        )
        .order('nombre');
    return filas.map(Parque.fromMap).toList(growable: false);
  }

  Future<Map<String, String>> nombresDePerfiles() async {
    final filas = await _client.from('perfiles').select('id, nombre_completo');
    return {
      for (final fila in filas)
        fila['id'] as String: fila['nombre_completo'] as String,
    };
  }
}
