import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';

/// Primera jornada abierta de la lista, si existe.
Jornada? jornadaAbiertaDe(List<Jornada> jornadas) {
  for (final jornada in jornadas) {
    if (jornada.abierta) return jornada;
  }
  return null;
}
