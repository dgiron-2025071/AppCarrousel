import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';

/// Parques donde se puede iniciar una jornada: solo los activos.
List<Parque> parquesParaEntrada(Iterable<Parque> parques) =>
    parques.where((parque) => parque.activo).toList(growable: false);

/// Parques que se muestran al marcar: los activos y, al cerrar, el parque de
/// la jornada abierta aunque se haya desactivado durante el turno.
///
/// La base de datos permite cerrar una jornada en su parque original sin exigir
/// que siga activo. Si la app solo cargara parques activos, ocultaría ese
/// parque y el empleado no podría cerrar el turno desde la aplicación.
List<Parque> parquesVisibles(Iterable<Parque> parques, Jornada? abierta) =>
    parques
        .where((parque) => parque.activo || parque.id == abierta?.parqueId)
        .toList(growable: false);

/// Devuelve el parque con el que se abrió la jornada, esté activo o no.
Parque? parqueDeJornada(Iterable<Parque> parques, Jornada? abierta) {
  if (abierta == null) return null;
  for (final parque in parques) {
    if (parque.id == abierta.parqueId) return parque;
  }
  return null;
}
