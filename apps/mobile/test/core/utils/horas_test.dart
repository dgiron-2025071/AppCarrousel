import 'package:carrousel_app/core/utils/horas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizarHora unifica HH:mm y HH:mm:ss', () {
    expect(normalizarHora('9:5:00'), '09:05');
    expect(normalizarHora('23:59:59'), '23:59');
    expect(normalizarHora('24:00'), '--:--');
    expect(normalizarHora(null), '--:--');
  });

  test('minutos y texto son inversos', () {
    expect(minutosDeHora('01:30'), 90);
    expect(horaDeMinutos(90), '01:30');
    expect(horaDeMinutos(1440), '00:00');
  });

  test('la franja con entrada y salida iguales es inválida', () {
    expect(validarFranja('09:00', '09:00'), isNotNull);
    expect(validarFranja('22:00', '06:00'), isNull);
    expect(validarFranja('09:00', '18:00'), isNull);
  });
}
