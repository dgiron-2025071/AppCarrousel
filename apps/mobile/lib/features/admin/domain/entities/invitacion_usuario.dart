import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';

/// Resultado de una invitación creada por un administrador.
///
/// La Edge Function `invitar-usuario` ya creó el usuario en Auth, envió el
/// correo y escribió los claims en `app_metadata`. La app solo refleja la
/// respuesta para confirmar el alcance asignado.
class InvitacionUsuario {
  const InvitacionUsuario({
    required this.id,
    required this.email,
    required this.rol,
    required this.empresaId,
    required this.centroCostoId,
    required this.nombreCompleto,
    required this.invitacionEnviada,
  });

  final String id;
  final String email;
  final RolUsuario rol;
  final String empresaId;
  final String centroCostoId;
  final String nombreCompleto;
  final bool invitacionEnviada;

  String get rolEtiqueta => rol.etiqueta;
}
