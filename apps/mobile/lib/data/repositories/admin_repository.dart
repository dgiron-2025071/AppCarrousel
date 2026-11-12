import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/error_messages.dart';
import '../models/admin_models.dart';
import '../models/jornada.dart';

/// Operaciones del módulo de administración. Todas pasan por RLS o por
/// funciones `security definer` que validan el alcance del admin.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<ResumenAdmin> resumen(String yo) async {
    final resultados = await Future.wait([
      _client.from('jornadas').select('id').isFilter('salida_en', null).neq('empleado_id', yo),
      _client.from('incidencias').select('id').eq('estado', 'abierta').neq('empleado_id', yo),
      _client
          .from('solicitudes_horas_extras')
          .select('id')
          .eq('estado', 'pendiente')
          .neq('empleado_id', yo),
      _client.from('registros').select('id').eq('estado', 'pendiente'),
    ]);
    return ResumenAdmin(
      enTurno: resultados[0].length,
      incidenciasAbiertas: resultados[1].length,
      solicitudesPendientes: resultados[2].length,
      registrosPendientes: resultados[3].length,
    );
  }

  // --- Registro ------------------------------------------------------------

  /// La solicitud propia del usuario actual (sin perfil todavía).
  Future<Registro?> miRegistro(String yo) async {
    final fila =
        await _client.from('registros').select().eq('id', yo).maybeSingle();
    return fila == null ? null : Registro.fromMap(fila);
  }

  Future<List<Registro>> registros() async {
    final filas = await _client
        .from('registros')
        .select()
        .order('creado_en', ascending: false)
        .limit(100);
    return filas.map(Registro.fromMap).toList(growable: false);
  }

  Future<void> aprobarRegistro({
    required String registroId,
    required String centroId,
    String? puestoId,
  }) =>
      _client.rpc('aprobar_registro', params: {
        'p_registro': registroId,
        'p_centro': centroId,
        'p_puesto': puestoId,
      });

  Future<void> rechazarRegistro({
    required String registroId,
    required String motivo,
  }) =>
      _client.rpc('rechazar_registro', params: {
        'p_registro': registroId,
        'p_motivo': motivo,
      });

  Future<List<({String id, String nombre})>> puestos() async {
    final filas = await _client
        .from('puestos')
        .select('id, nombre')
        .eq('activo', true)
        .order('nombre');
    return [
      for (final f in filas)
        (id: f['id'] as String, nombre: f['nombre'] as String),
    ];
  }

  // --- Lugares (parques, Oficina Central, Bodega) --------------------------

  /// Crea o actualiza un lugar con su geocerca. RLS exige que su centro de
  /// costo esté en el alcance del admin.
  Future<void> guardarLugar({
    String? id,
    required String empresaId,
    required String centroCostoId,
    required String codigo,
    required String nombre,
    String? direccion,
    required double latitud,
    required double longitud,
    required double radioMetros,
    bool activo = true,
  }) async {
    final datos = {
      'activo': activo,
      'centro_costo_id': centroCostoId,
      'codigo': codigo.trim().toUpperCase(),
      'nombre': nombre.trim(),
      'direccion': (direccion?.trim().isEmpty ?? true) ? null : direccion!.trim(),
      'latitud': latitud,
      'longitud': longitud,
      'radio_metros': radioMetros.round(),
    };
    if (id == null) {
      await _client.from('parques').insert({...datos, 'empresa_id': empresaId});
      return;
    }
    final filas =
        await _client.from('parques').update(datos).eq('id', id).select('id');
    if (filas.isEmpty) {
      throw const AppException('No tienes permiso para editar este lugar.');
    }
  }

  /// Borra el lugar; si ya tiene jornadas u horarios, se desactiva para
  /// conservar el historial.
  Future<bool> eliminarLugar(String id) async {
    try {
      final filas =
          await _client.from('parques').delete().eq('id', id).select('id');
      if (filas.isEmpty) {
        throw const AppException('No tienes permiso para eliminar este lugar.');
      }
      return true;
    } on PostgrestException catch (error) {
      if (error.code != '23503') rethrow;
      await _client.from('parques').update({'activo': false}).eq('id', id);
      return false;
    }
  }

  Future<void> agregarCentroALugar({
    required String empresaId,
    required String lugarId,
    required String centroId,
  }) =>
      _client.from('parques_centros').insert({
        'empresa_id': empresaId,
        'parque_id': lugarId,
        'centro_costo_id': centroId,
      });

  Future<void> quitarCentroDeLugar({
    required String lugarId,
    required String centroId,
  }) =>
      _client
          .from('parques_centros')
          .delete()
          .eq('parque_id', lugarId)
          .eq('centro_costo_id', centroId);

  // --- Centros de costo ----------------------------------------------------

  Future<void> guardarCentro({
    String? id,
    required String empresaId,
    String? padreId,
    required String codigo,
    required String nombre,
  }) async {
    final datos = {'codigo': codigo.trim(), 'nombre': nombre.trim()};
    if (id == null) {
      await _client.from('centros_costo').insert({
        ...datos,
        'empresa_id': empresaId,
        'padre_id': padreId,
      });
      return;
    }
    final filas = await _client
        .from('centros_costo')
        .update(datos)
        .eq('id', id)
        .select('id');
    if (filas.isEmpty) {
      throw const AppException('No tienes permiso para editar este centro.');
    }
  }

  Future<void> eliminarCentro(String id) async {
    try {
      final filas =
          await _client.from('centros_costo').delete().eq('id', id).select('id');
      if (filas.isEmpty) {
        throw const AppException('No tienes permiso para eliminar este centro.');
      }
    } on PostgrestException catch (error) {
      if (error.code == '23503') {
        throw const AppException(
          'No se puede eliminar: tiene sub-centros, lugares, personas o '
          'solicitudes asociadas.',
        );
      }
      rethrow;
    }
  }

  // --- Incidencias ---------------------------------------------------------

  Future<List<Incidencia>> incidencias({required bool abiertas}) async {
    final consulta = _client.from('incidencias').select();
    final filas = await (abiertas
            ? consulta.eq('estado', 'abierta')
            : consulta.neq('estado', 'abierta'))
        .order('creado_en', ascending: false)
        .limit(100);
    return filas.map(Incidencia.fromMap).toList(growable: false);
  }

  Future<void> cerrarIncidencia({
    required String id,
    required bool descartar,
    required String nota,
  }) async {
    final filas = await _client
        .from('incidencias')
        .update({
          'estado': descartar ? 'descartada' : 'resuelta',
          'resolucion': nota.trim(),
        })
        .eq('id', id)
        .select('id');
    if (filas.isEmpty) {
      throw const AppException(
        'La incidencia ya fue cerrada o no tienes permiso.',
      );
    }
  }

  // --- Jornadas del equipo -------------------------------------------------

  Future<List<Jornada>> jornadasEquipo({
    required String yo,
    required DateTime desde,
  }) async {
    final filas = await _client
        .from('jornadas')
        .select()
        .neq('empleado_id', yo)
        .gte('entrada_en', desde.toUtc().toIso8601String())
        .order('entrada_en', ascending: false)
        .limit(200);
    return filas.map(Jornada.fromMap).toList(growable: false);
  }

  Future<void> ajustarJornada({
    required String jornadaId,
    required DateTime entrada,
    required DateTime salida,
    required String motivo,
  }) =>
      _client.rpc('ajustar_jornada', params: {
        'p_jornada': jornadaId,
        'p_entrada': entrada.toUtc().toIso8601String(),
        'p_salida': salida.toUtc().toIso8601String(),
        'p_motivo': motivo.trim(),
      });
}
