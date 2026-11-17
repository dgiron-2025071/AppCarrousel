import 'package:carrousel_app/core/utils/zonas_horarias.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const zona = 'America/Guatemala';
  final instante = DateTime.utc(2026, 11, 17, 3);

  test('el resumen usa la fecha de la empresa, no la del dispositivo', () {
    final local = ahoraEnZona(zona, instante: instante);

    // Guatemala es UTC-6: son las 21:00 del día anterior.
    expect(local.toUtc(), instante);
    expect(local.day, 16);
    expect(local.hour, 21);

    expect(
      inicioDelDiaEnZona(local, zona).toUtc(),
      DateTime.utc(2026, 11, 16, 6),
    );
    expect(finDelDiaEnZona(local, zona).toUtc(), DateTime.utc(2026, 11, 17, 6));
  });

  test('inicio de semana y de mes se calculan en la zona de la empresa', () {
    final local = ahoraEnZona(zona, instante: instante);

    // El 16 de noviembre de 2026 es lunes.
    expect(
      inicioSemanaEnZona(local, zona).toUtc(),
      DateTime.utc(2026, 11, 16, 6),
    );
    expect(inicioMesEnZona(local, zona).toUtc(), DateTime.utc(2026, 11, 1, 6));
  });

  test('valida la zona contra la base IANA, no por su longitud', () {
    expect(zonaHorariaValida('America/Guatemala'), isTrue);
    expect(zonaHorariaValida('UTC'), isTrue);
    expect(zonaHorariaValida('Zona/Invalida'), isFalse);
    expect(zonaHorariaValida(' America/Guatemala '), isTrue);
    expect(zonaHorariaValida('AB/CD'), isFalse);
  });

  test('una zona inesperada cae a UTC en lugar de usar la del dispositivo', () {
    expect(ahoraEnZona('Zona/Invalida', instante: instante).toUtc(), instante);
    expect(
      inicioDelDiaEnZona(instante, 'Zona/Invalida').toUtc(),
      DateTime.utc(2026, 11, 17),
    );
  });
}
