import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/horas_extra.dart';
import '../data/models/admin_models.dart';
import '../data/models/centro_costo.dart';
import '../data/models/horario.dart';
import '../data/models/jornada.dart';
import '../data/models/parque.dart';
import '../data/models/perfil.dart';
import '../data/models/solicitud_horas_extras.dart';
import '../data/repositories/admin_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/catalogo_repository.dart';
import '../data/repositories/horario_repository.dart';
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

final horarioRepositoryProvider = Provider<HorarioRepository>(
  (ref) => HorarioRepository(ref.watch(supabaseProvider)),
);

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(supabaseProvider)),
);

final catalogoRepositoryProvider = Provider<CatalogoRepository>(
  (ref) => CatalogoRepository(ref.watch(supabaseProvider)),
);

final invitacionRepositoryProvider = Provider<InvitacionGateway>(
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

final jornadasStreamProvider = StreamProvider.autoDispose<List<Jornada>>((ref) {
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
        final solicitudes = filas.map(SolicitudHorasExtras.fromMap).toList();
        solicitudes.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
        return solicitudes;
      });
});

final centrosProvider = FutureProvider.autoDispose<List<CentroCosto>>((
  ref,
) async {
  return ref.watch(catalogoRepositoryProvider).centros();
});

final centrosPorLugarProvider =
    FutureProvider.autoDispose<Map<String, Set<String>>>((ref) {
  return ref.watch(catalogoRepositoryProvider).centrosPorLugar();
});

final parquesProvider = FutureProvider.autoDispose<List<Parque>>((ref) async {
  return ref.watch(catalogoRepositoryProvider).parques();
});

final personasProvider =
    FutureProvider.autoDispose<Map<String, PersonaResumen>>((ref) async {
  return ref.watch(catalogoRepositoryProvider).personas();
});

/// Jefe que autoriza las solicitudes del usuario actual (null si nadie).
final miAutorizadorProvider = FutureProvider.autoDispose<PersonaResumen?>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(solicitudRepositoryProvider).miAutorizador();
});

/// Une el stream de Realtime con los nombres de especialistas y centros.
/// Las RLS ya limitan ambos catálogos al ámbito del usuario.
final solicitudesDetalladasProvider =
    Provider.autoDispose<AsyncValue<List<SolicitudDetalle>>>((ref) {
  final solicitudes = ref.watch(solicitudesStreamProvider);
  final personas = ref.watch(personasProvider);
  final centros = ref.watch(centrosProvider);

  return solicitudes.when(
    loading: () => const AsyncLoading(),
    error: (error, stack) => AsyncError(error, stack),
    data: (filas) {
      final mapaPersonas = personas.valueOrNull;
      final listaCentros = centros.valueOrNull;
      if (mapaPersonas == null || listaCentros == null) {
        return const AsyncLoading();
      }
      final mapaCentros = {
        for (final centro in listaCentros) centro.id: centro.etiqueta,
      };
      final detalles = filas.map((solicitud) {
        final persona = mapaPersonas[solicitud.empleadoId];
        return SolicitudDetalle(
          solicitud: solicitud,
          empleadoNombre: persona?.nombre ?? 'Especialista',
          empleadoPuesto: persona?.puesto,
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

/// Horario semanal de un empleado (el propio o, para un admin, su equipo).
final horariosDeProvider =
    FutureProvider.autoDispose.family<List<Horario>, String>((ref, id) {
  return ref.watch(horarioRepositoryProvider).horariosDe(id);
});

/// Jornadas de los últimos 30 días con horas extra detectadas por GPS que aún
/// no se han solicitado. Se recalcula cuando cambian jornadas o solicitudes.
final horasExtraPorSolicitarProvider =
    FutureProvider.autoDispose<List<CumplimientoJornada>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  ref.watch(jornadasStreamProvider);
  ref.watch(solicitudesStreamProvider);
  final filas = await ref.watch(horarioRepositoryProvider).cumplimientoPropio(
        empleadoId: user.id,
        desde: DateTime.now().subtract(const Duration(days: 30)),
      );
  return horasExtraPorSolicitar(filas);
});

// --- Registro y módulo de administración ---------------------------------

/// Solicitud de registro del usuario sin perfil (cuenta pendiente).
final miRegistroProvider = FutureProvider.autoDispose<Registro?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(adminRepositoryProvider).miRegistro(user.id);
});

final resumenAdminProvider =
    FutureProvider.autoDispose<ResumenAdmin>((ref) async {
  final user = ref.watch(currentUserProvider);
  ref.watch(solicitudesStreamProvider);
  return ref.watch(adminRepositoryProvider).resumen(user?.id ?? '');
});

final registrosProvider = FutureProvider.autoDispose<List<Registro>>((ref) {
  return ref.watch(adminRepositoryProvider).registros();
});

final incidenciasProvider =
    FutureProvider.autoDispose.family<List<Incidencia>, bool>((ref, abiertas) {
  return ref.watch(adminRepositoryProvider).incidencias(abiertas: abiertas);
});

final puestosProvider =
    FutureProvider.autoDispose<List<({String id, String nombre})>>((ref) {
  return ref.watch(adminRepositoryProvider).puestos();
});

/// Jornadas del equipo de los últimos 14 días.
final jornadasEquipoProvider =
    FutureProvider.autoDispose<List<Jornada>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(adminRepositoryProvider).jornadasEquipo(
        yo: user.id,
        desde: DateTime.now().subtract(const Duration(days: 14)),
      );
});
