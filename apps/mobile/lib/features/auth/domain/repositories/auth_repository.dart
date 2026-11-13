import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/sesion_usuario.dart';

/// Eventos de sesión que la capa de presentación puede observar sin depender
/// de los tipos de Supabase.
enum EventoSesion {
  iniciada,
  cerrada,
  recuperacionContrasena,
  actualizada,
}

/// Contrato de autenticación. La implementación concreta vive en `data`.
abstract class AuthRepository {
  Stream<EventoSesion> get eventosDeSesion;

  SesionUsuario? get sesionActual;

  Future<void> iniciarSesion({
    required String email,
    required String password,
  });

  /// Devuelve true si se abrió el navegador. El resultado real llega por
  /// [eventosDeSesion] cuando Supabase procesa el deep link.
  Future<bool> iniciarConGoogle();

  Future<void> enviarRecuperacion(String email);

  Future<void> actualizarContrasena(String password);

  Future<void> cerrarSesion();

  Future<Perfil?> obtenerPerfil(String userId);
}
