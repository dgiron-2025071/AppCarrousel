import 'package:carrousel_app/core/supabase/supabase_provider.dart';
import 'package:carrousel_app/features/auth/data/repositories/supabase_auth_repository.dart';
import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/sesion_usuario.dart';
import 'package:carrousel_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:carrousel_app/features/auth/domain/usecases/auth_usecases.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseProvider)),
);

final eventosSesionProvider = StreamProvider<EventoSesion>(
  (ref) => ref.watch(authRepositoryProvider).eventosDeSesion,
);

/// Sesión actual. Se recalcula con cada evento de Auth.
final sesionActualProvider = Provider<SesionUsuario?>((ref) {
  ref.watch(eventosSesionProvider);
  return ref.watch(authRepositoryProvider).sesionActual;
});

final perfilProvider = FutureProvider.autoDispose<Perfil?>((ref) async {
  final sesion = ref.watch(sesionActualProvider);
  if (sesion == null) return null;
  return ObtenerPerfil(ref.watch(authRepositoryProvider))(sesion.id);
});
