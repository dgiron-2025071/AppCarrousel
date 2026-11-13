import 'package:carrousel_app/features/admin/domain/entities/invitacion_usuario.dart';
import 'package:carrousel_app/features/admin/domain/repositories/invitacion_repository.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';

class InvitarUsuario {
  const InvitarUsuario(this._repo);

  final InvitacionRepository _repo;

  Future<InvitacionUsuario> call({
    required String email,
    required String nombreCompleto,
    required RolUsuario rol,
    required String centroCostoId,
  }) =>
      _repo.invitar(
        email: email,
        nombreCompleto: nombreCompleto,
        rol: rol,
        centroCostoId: centroCostoId,
      );
}
