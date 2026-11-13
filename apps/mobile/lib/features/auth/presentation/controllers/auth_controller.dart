import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:carrousel_app/features/auth/domain/usecases/auth_usecases.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._auth) : super(const AsyncData(null));

  final AuthRepository _auth;

  Future<bool> _ejecutar(Future<void> Function() accion) async {
    state = const AsyncLoading();
    try {
      await accion();
      state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      state = AsyncError(mensajeDeError(error), stack);
      return false;
    }
  }

  Future<bool> iniciarSesion({
    required String email,
    required String password,
  }) {
    return _ejecutar(
      () => IniciarSesion(_auth)(email: email, password: password),
    );
  }

  Future<bool> iniciarConGoogle() {
    return _ejecutar(() async {
      final abierto = await IniciarConGoogle(_auth)();
      if (!abierto) {
        throw const AppException(
          'No se pudo abrir el navegador para iniciar con Google.',
        );
      }
    });
  }

  Future<bool> enviarRecuperacion(String email) {
    return _ejecutar(() => EnviarRecuperacion(_auth)(email));
  }

  Future<bool> actualizarContrasena(String password) {
    return _ejecutar(() => ActualizarContrasena(_auth)(password));
  }

  Future<bool> cerrarSesion() => _ejecutar(CerrarSesion(_auth).call);

  void limpiarError() {
    if (state.hasError) state = const AsyncData(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});
