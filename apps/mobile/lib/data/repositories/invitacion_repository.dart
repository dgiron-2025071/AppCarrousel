import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/error_messages.dart';
import '../models/invitacion_usuario.dart';

/// Cliente de la Edge Function `invitar-usuario`.
///
/// La función valida que el solicitante sea un administrador activo y que el
/// centro destino esté dentro de su subárbol. La app nunca escribe claims ni
/// crea usuarios directamente: solo envía el formulario.
class InvitacionRepository {
  InvitacionRepository(this._client);

  final SupabaseClient _client;

  Future<InvitacionUsuario> invitar({
    required String email,
    required String nombreCompleto,
    required String rol,
    required String centroCostoId,
  }) async {
    try {
      final respuesta = await _client.functions.invoke(
        'invitar-usuario',
        body: {
          'email': email.trim(),
          'nombre_completo': nombreCompleto.trim(),
          'rol': rol,
          'centro_costo_id': centroCostoId,
        },
      );

      final datos = respuesta.data;
      if (datos is! Map<String, dynamic>) {
        throw const AppException(
          'La invitación se envió, pero la respuesta del servidor no fue válida.',
        );
      }
      return InvitacionUsuario.fromMap(datos);
    } on FunctionException catch (error) {
      throw AppException(_mensajeDeFuncion(error));
    }
  }
}

String _mensajeDeFuncion(FunctionException error) {
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
