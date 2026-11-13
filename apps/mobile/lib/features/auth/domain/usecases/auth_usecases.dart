import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/repositories/auth_repository.dart';

class IniciarSesion {
  const IniciarSesion(this._repo);

  final AuthRepository _repo;

  Future<void> call({required String email, required String password}) =>
      _repo.iniciarSesion(email: email, password: password);
}

class IniciarConGoogle {
  const IniciarConGoogle(this._repo);

  final AuthRepository _repo;

  Future<bool> call() => _repo.iniciarConGoogle();
}

class EnviarRecuperacion {
  const EnviarRecuperacion(this._repo);

  final AuthRepository _repo;

  Future<void> call(String email) => _repo.enviarRecuperacion(email);
}

class ActualizarContrasena {
  const ActualizarContrasena(this._repo);

  final AuthRepository _repo;

  Future<void> call(String password) => _repo.actualizarContrasena(password);
}

class CerrarSesion {
  const CerrarSesion(this._repo);

  final AuthRepository _repo;

  Future<void> call() => _repo.cerrarSesion();
}

class ObtenerPerfil {
  const ObtenerPerfil(this._repo);

  final AuthRepository _repo;

  Future<Perfil?> call(String userId) => _repo.obtenerPerfil(userId);
}
