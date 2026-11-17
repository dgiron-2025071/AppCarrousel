import 'package:carrousel_app/core/utils/correos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acepta correos con formato estándar y recorta espacios', () {
    expect(correoValido('ana@carrousel.test'), isTrue);
    expect(correoValido('  ana.perez@correo.com  '), isTrue);
  });

  test('rechaza texto sin @, sin dominio o con espacios internos', () {
    expect(correoValido('ana'), isFalse);
    expect(correoValido('ana@correo'), isFalse);
    expect(correoValido('ana@correo .com'), isFalse);
    expect(correoValido(''), isFalse);
    expect(correoValido(null), isFalse);
  });

  test('rechaza correos que superan el límite de 320 caracteres', () {
    final largo = '${'a' * 310}@correo.com';
    expect(largo.length, greaterThan(longitudMaximaCorreo));
    expect(correoValido(largo), isFalse);
  });
}
