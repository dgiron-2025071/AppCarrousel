import 'package:carrousel_app/features/admin/domain/entities/invitacion_usuario.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';

/// Contrato del cliente de invitaciones, para poder sustituirlo en pruebas.
abstract class InvitacionRepository {
  Future<InvitacionUsuario> invitar({
    required String email,
    required String nombreCompleto,
    required RolUsuario rol,
    required String centroCostoId,
  });
}
