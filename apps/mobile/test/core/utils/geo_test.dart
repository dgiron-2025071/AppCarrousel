import 'dart:math';

import 'package:carrousel_app/core/utils/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('distanciaMetros reproduce la haversine de PostgreSQL', () {
    // Un grado de latitud en el ecuador son ~111 195 m.
    expect(distanciaMetros(0, 0, 1, 0), closeTo(111195, 5));
    expect(distanciaMetros(0, 0, 0, 0), 0);
    expect(distanciaMetros(14.6349, -90.5069, 14.6350, -90.5069), lessThan(20));
    // La función es simétrica.
    expect(
      distanciaMetros(0, 0, 1, 0),
      closeTo(distanciaMetros(1, 0, 0, 0), 0.001),
    );
  });

  test('la tolerancia GPS se limita al rango de la base', () {
    expect(toleranciaGps(0), 0);
    expect(toleranciaGps(50), 50);
    expect(toleranciaGps(100), 100);
    expect(toleranciaGps(150), 100);
    expect(toleranciaGps(-20), 0);
    expect(toleranciaGps(double.infinity), 100);
  });

  test('puntos antipodales no superan la circunferencia terrestre', () {
    expect(distanciaMetros(0, 0, 0, 180), closeTo(pi * 6371000, 1));
  });
}
