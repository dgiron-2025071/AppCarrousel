import 'package:carrousel_app/data/models/invitacion_usuario.dart';
import 'package:carrousel_app/data/repositories/invitacion_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mensajeDeErrorDeFuncion', () {
    test('sin conexión', () {
      expect(
        mensajeDeErrorDeFuncion(const FunctionException(status: 0)),
        contains('Sin conexión'),
      );
    });

    test('sesión expirada', () {
      expect(
        mensajeDeErrorDeFuncion(const FunctionException(status: 401)),
        contains('sesión expiró'),
      );
    });

    test('usa el mensaje del servidor para 403', () {
      const error = FunctionException(
        status: 403,
        details: {'error': 'Solo puedes invitar dentro de tu subárbol.'},
      );

      expect(
        mensajeDeErrorDeFuncion(error),
        'Solo puedes invitar dentro de tu subárbol.',
      );
    });

    test('correo duplicado', () {
      expect(
        mensajeDeErrorDeFuncion(const FunctionException(status: 409)),
        contains('ya tiene una cuenta'),
      );
    });

    test('validación 400 con detalle del servidor', () {
      const error = FunctionException(
        status: 400,
        details: {'error': 'Escribe un correo electrónico válido.'},
      );

      expect(
        mensajeDeErrorDeFuncion(error),
        'Escribe un correo electrónico válido.',
      );
    });

    test('error de configuración 500', () {
      expect(
        mensajeDeErrorDeFuncion(const FunctionException(status: 500)),
        contains('no está configurada'),
      );
    });

    test('error de envío de correo 502', () {
      expect(
        mensajeDeErrorDeFuncion(const FunctionException(status: 502)),
        contains('configuración de correo'),
      );
    });

    test('acepta detalles en texto plano', () {
      const error = FunctionException(
        status: 400,
        details: 'El centro de costo no es válido.',
      );

      expect(
        mensajeDeErrorDeFuncion(error),
        'El centro de costo no es válido.',
      );
    });
  });

  group('InvitacionUsuario.fromMap', () {
    test('lee la respuesta de la Edge Function', () {
      final invitacion = InvitacionUsuario.fromMap({
        'id': 'uuid',
        'email': 'ana@carrousel.test',
        'rol': 'admin',
        'empresa_id': 'empresa',
        'centro_costo_id': 'centro',
        'nombre_completo': 'Ana Pérez',
        'invitacion_enviada': true,
      });

      expect(invitacion.email, 'ana@carrousel.test');
      expect(invitacion.rolEtiqueta, 'Administrador');
      expect(invitacion.invitacionEnviada, isTrue);
    });
  });
}
