import 'package:carrousel_app/features/admin/domain/entities/invitacion_usuario.dart';
import 'package:carrousel_app/features/admin/domain/repositories/invitacion_repository.dart';
import 'package:carrousel_app/features/admin/domain/usecases/invitar_usuario.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controla el envío de invitaciones y expone el error ya traducido.
class InvitacionController extends StateNotifier<AsyncValue<void>> {
  InvitacionController(this._repo) : super(const AsyncData(null));

  final InvitacionRepository _repo;

  Future<InvitacionUsuario?> invitar({
    required String email,
    required String nombreCompleto,
    required RolUsuario rol,
    required String centroCostoId,
  }) async {
    state = const AsyncLoading();
    try {
      final invitacion = await InvitarUsuario(_repo)(
        email: email,
        nombreCompleto: nombreCompleto,
        rol: rol,
        centroCostoId: centroCostoId,
      );
      state = const AsyncData(null);
      return invitacion;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      rethrow;
    }
  }
}
