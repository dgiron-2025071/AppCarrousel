import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../data/repositories/auth_repository.dart';
import '../../providers/app_providers.dart';

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._repo) : super(const AsyncData(null));

  final AuthRepository _repo;

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
    return _ejecutar(() => _repo.iniciarSesion(email: email, password: password));
  }

  Future<bool> iniciarConGoogle() {
    return _ejecutar(() async {
      final abierto = await _repo.iniciarConGoogle();
      if (!abierto) {
        throw const AppException(
          'No se pudo abrir el navegador para iniciar con Google.',
        );
      }
    });
  }

  Future<bool> enviarRecuperacion(String email) {
    return _ejecutar(() => _repo.enviarRecuperacion(email));
  }

  Future<bool> actualizarContrasena(String password) {
    return _ejecutar(() => _repo.actualizarContrasena(password));
  }

  Future<bool> cerrarSesion() => _ejecutar(_repo.cerrarSesion);

  void limpiarError() {
    if (state.hasError) state = const AsyncData(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});
