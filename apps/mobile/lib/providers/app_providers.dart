import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/centro_costo.dart';
import '../data/models/jornada.dart';
import '../data/models/parque.dart';
import '../data/models/perfil.dart';
import '../data/models/solicitud_horas_extras.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/catalogo_repository.dart';
import '../data/repositories/invitacion_repository.dart';
import '../data/repositories/jornada_repository.dart';
import '../data/repositories/solicitud_repository.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

final jornadaRepositoryProvider = Provider<JornadaRepository>(
  (ref) => JornadaRepository(ref.watch(supabaseProvider)),
);

final solicitudRepositoryProvider = Provider<SolicitudRepository>(
  (ref) => SolicitudRepository(ref.watch(supabaseProvider)),
);

final catalogoRepositoryProvider = Provider<CatalogoRepository>(
  (ref) => CatalogoRepository(ref.watch(supabaseProvider)),
);

final invitacionRepositoryProvider = Provider<InvitacionRepository>(
  (ref) => InvitacionRepository(ref.watch(supabaseProvider)),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).cambiosDeSesion,
);

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

final perfilProvider = FutureProvider.autoDispose<Perfil?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(authRepositoryProvider).obtenerPerfil(user.id);
});

final jornadasStreamProvider =
    StreamProvider.autoDispose<List<Jornada>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();
  return ref
      .watch(supabaseProvider)
      .from('jornadas')
      .stream(primaryKey: ['id'])
      .eq('empleado_id', user.id)
      .order('entrada_en', ascending: false)
      .map((filas) {
        // Realtime agrega las filas nuevas al final; se reordena en cliente
        // para que el último marcaje siempre quede primero.
        final jornadas = filas.map(Jornada.fromMap).toList();
        jornadas.sort((a, b) => b.entradaEn.compareTo(a.entradaEn));
        return jornadas;
      });
});

final solicitudesStreamProvider =
    StreamProvider.autoDispose<List<SolicitudHorasExtras>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();
  return ref
      .watch(supabaseProvider)
      .from('solicitudes_horas_extras')
      .stream(primaryKey: ['id'])
      .order('creado_en', ascending: false)
      .map((filas) {
        final solicitudes =
            filas.map(SolicitudHorasExtras.fromMap).toList();
        solicitudes.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
        return solicitudes;
      });
});

final centrosProvider =
    FutureProvider.autoDispose<List<CentroCosto>>((ref) async {
  return ref.watch(catalogoRepositoryProvider).centros();
});

final parquesProvider = FutureProvider.autoDispose<List<Parque>>((ref) async {
  return ref.watch(catalogoRepositoryProvider).parques();
});

final nombresPerfilesProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  return ref.watch(catalogoRepositoryProvider).nombresDePerfiles();
});

/// Une el stream de Realtime con los nombres de especialistas y centros.
/// Las RLS ya limitan ambos catálogos al ámbito del usuario.
final solicitudesDetalladasProvider =
    Provider.autoDispose<AsyncValue<List<SolicitudDetalle>>>((ref) {
  final solicitudes = ref.watch(solicitudesStreamProvider);
  final nombres = ref.watch(nombresPerfilesProvider);
  final centros = ref.watch(centrosProvider);

  return solicitudes.when(
    loading: () => const AsyncLoading(),
    error: (error, stack) => AsyncError(error, stack),
    data: (filas) {
      final mapaNombres = nombres.valueOrNull;
      final listaCentros = centros.valueOrNull;
      if (mapaNombres == null || listaCentros == null) {
        return const AsyncLoading();
      }
      final mapaCentros = {
        for (final centro in listaCentros) centro.id: centro.nombre,
      };
      final detalles = filas.map((solicitud) {
        return SolicitudDetalle(
          solicitud: solicitud,
          empleadoNombre:
              mapaNombres[solicitud.empleadoId] ?? 'Especialista',
          centroNombre:
              mapaCentros[solicitud.centroCostoId] ?? 'Centro de costo',
        );
      }).toList(growable: false);
      return AsyncData(detalles);
    },
  );
});

Jornada? jornadaAbiertaDe(List<Jornada> jornadas) {
  for (final jornada in jornadas) {
    if (jornada.abierta) return jornada;
  }
  return null;
}
