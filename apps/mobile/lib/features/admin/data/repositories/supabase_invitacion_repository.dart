import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/features/admin/data/mappers/invitacion_mapper.dart';
import 'package:carrousel_app/features/admin/domain/entities/invitacion_usuario.dart';
import 'package:carrousel_app/features/admin/domain/repositories/invitacion_repository.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cliente de la Edge Function `invitar-usuario`.
///
/// La función valida que el solicitante sea un administrador activo y que el
/// centro destino esté dentro de su subárbol. La app nunca escribe claims ni
/// crea usuarios directamente: solo envía el formulario.
class SupabaseInvitacionRepository implements InvitacionRepository {
  SupabaseInvitacionRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<InvitacionUsuario> invitar({
    required String email,
    required String nombreCompleto,
    required RolUsuario rol,
    required String centroCostoId,
  }) async {
    try {
      final respuesta = await _client.functions.invoke(
        'invitar-usuario',
        body: {
          'email': email.trim(),
          'nombre_completo': nombreCompleto.trim(),
          'rol': rol.name,
          'centro_costo_id': centroCostoId,
        },
      );

      final datos = respuesta.data;
      if (datos is! Map<String, dynamic>) {
        throw const AppException(
          'La invitación se envió, pero la respuesta del servidor no fue válida.',
        );
      }
      return invitacionDesdeMapa(datos);
    } on FunctionException catch (error) {
      throw AppException(mensajeDeErrorDeFuncion(error));
    }
  }
}

String mensajeDeErrorDeFuncion(FunctionException error) {
  final mensaje = _detalleDeError(error.details);

  switch (error.status) {
    case 0:
      return 'Sin conexión. Revisa tu red e inténtalo de nuevo.';
    case 401:
      return 'Tu sesión expiró. Vuelve a iniciar sesión.';
    case 403:
      return mensaje ??
          'Solo un administrador puede invitar usuarios dentro de su subárbol.';
    case 409:
      return 'Ese correo ya tiene una cuenta en Carrousel.';
    case 400:
      return mensaje ?? 'Revisa los datos de la invitación.';
    case 502:
      return 'No se pudo enviar la invitación. Revisa la configuración de correo.';
    case 500:
      return mensaje ??
          'La función de invitación no está configurada correctamente.';
    default:
      return mensaje ?? 'No se pudo enviar la invitación. Inténtalo de nuevo.';
  }
}

String? _detalleDeError(Object? detalles) {
  if (detalles is Map) {
    final valor = detalles['error'];
    if (valor is String) {
      final texto = valor.trim();
      if (texto.isNotEmpty) return texto;
    }
  }
  if (detalles is String) {
    final texto = detalles.trim();
    if (texto.isNotEmpty && texto.length <= 300) return texto;
  }
  return null;
}
