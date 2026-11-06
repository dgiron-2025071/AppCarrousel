import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/errors/error_messages.dart';
import '../models/perfil.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get cambiosDeSesion => _client.auth.onAuthStateChange;

  User? get usuarioActual => _client.auth.currentUser;

  Future<void> iniciarSesion({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Devuelve true si se abrió el navegador. El resultado real llega por
  /// [cambiosDeSesion] cuando Supabase procesa el deep link.
  Future<bool> iniciarConGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Env.oauthRedirect,
    );
  }

  Future<void> enviarRecuperacion(String email) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: Env.oauthRedirect,
    );
  }

  Future<void> actualizarContrasena(String password) async {
    if (password.length < 8) {
      throw const AppException('La contraseña debe tener al menos 8 caracteres.');
    }
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> cerrarSesion() => _client.auth.signOut();

  Future<Perfil?> obtenerPerfil(String userId) async {
    final data = await _client
        .from('perfiles')
        .select('*, centros_costo!perfiles_centro_fk(nombre)')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return Perfil.fromMap(data);
  }
}
