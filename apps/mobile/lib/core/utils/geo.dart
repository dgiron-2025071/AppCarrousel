import 'dart:math' as math;

const double _radioTierraMetros = 6371000;

/// Distancia haversine en metros. Espejo de `private.distancia_metros()`.
double distanciaMetros(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final dLat = _radianes(lat2 - lat1);
  final dLon = _radianes(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radianes(lat1)) *
          math.cos(_radianes(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return _radioTierraMetros * 2 * math.asin(math.min(1, math.sqrt(a)));
}

double _radianes(double grados) => grados * math.pi / 180;

/// Misma tolerancia que la base: la precisión del GPS se suma al radio, con
/// un máximo de 100 m.
double toleranciaGps(double precisionMetros) =>
    precisionMetros.clamp(0, 100).toDouble();
