import 'package:carrousel_app/core/config/env.dart';
import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/features/auth/data/mappers/perfil_mapper.dart';
import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/sesion_usuario.dart';
import 'package:carrousel_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Implementación de autenticación sobre Supabase.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<EventoSesion> get eventosDeSesion =>
      _client.auth.onAuthStateChange.map((estado) {
        if (estado.event == AuthChangeEvent.signedOut) {
          return EventoSesion.cerrada;
        }
        if (estado.event == AuthChangeEvent.passwordRecovery) {
          return EventoSesion.recuperacionContrasena;
        }
        if (estado.event == AuthChangeEvent.userUpdated ||
            estado.event == AuthChangeEvent.tokenRefreshed) {
          return EventoSesion.actualizada;
        }
        return EventoSesion.iniciada;
      });

  @override
  SesionUsuario? get sesionActual {
    final usuario = _client.auth.currentUser;
    if (usuario == null) return null;
    return SesionUsuario(id: usuario.id, email: usuario.email ?? '');
  }

  @override
  Future<void> iniciarSesion({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<bool> iniciarConGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Env.oauthRedirect,
    );
  }

  @override
  Future<void> enviarRecuperacion(String email) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: Env.oauthRedirect,
    );
  }

  @override
  Future<void> actualizarContrasena(String password) async {
    if (password.length < 8) {
      throw const AppException(
        'La contraseña debe tener al menos 8 caracteres.',
      );
    }
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> cerrarSesion() => _client.auth.signOut();

  @override
  Future<Perfil?> obtenerPerfil(String userId) async {
    final data = await _client
        .from('perfiles')
        .select('*, centros_costo!perfiles_centro_fk(nombre)')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return perfilDesdeMapa(data);
  }
}
