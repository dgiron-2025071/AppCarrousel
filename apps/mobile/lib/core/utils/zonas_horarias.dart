import 'package:carrousel_app/core/utils/duraciones.dart';
import 'package:timezone/data/latest.dart' as datos;
import 'package:timezone/timezone.dart' as tz;

/// Zona usada mientras no se carga la configuración de la empresa.
const zonaHorariaPorDefecto = 'America/Guatemala';

bool _inicializado = false;

void _inicializar() {
  if (_inicializado) return;
  datos.initializeTimeZones();
  _inicializado = true;
}

tz.Location? _buscar(String zonaHoraria) {
  _inicializar();
  return tz.timeZoneDatabase.locations[zonaHoraria];
}

/// Comprueba la zona contra la base de datos IANA real, no solo su longitud.
/// PostgreSQL también acepta `UTC` como abreviatura, aunque el paquete
/// `timezone` no lo exponga como clave de su base.
bool zonaHorariaValida(String zonaHoraria) {
  final texto = zonaHoraria.trim();
  if (texto.toUpperCase() == 'UTC') return true;
  return _buscar(texto) != null;
}

tz.Location _location(String zonaHoraria) {
  // La base valida la zona IANA; si el cliente recibe un valor inesperado,
  // falla cerrado a UTC en lugar de usar la zona del dispositivo.
  return _buscar(zonaHoraria) ?? tz.UTC;
}

/// Instante actual expresado en la zona horaria de la empresa.
DateTime ahoraEnZona(String zonaHoraria, {DateTime? instante}) =>
    tz.TZDateTime.from(instante ?? DateTime.now(), _location(zonaHoraria));

DateTime _medianoche(DateTime fecha, tz.Location location) =>
    tz.TZDateTime(location, fecha.year, fecha.month, fecha.day);

DateTime inicioDelDiaEnZona(DateTime fecha, String zonaHoraria) =>
    _medianoche(fecha, _location(zonaHoraria));

DateTime finDelDiaEnZona(DateTime fecha, String zonaHoraria) =>
    _medianoche(fecha.add(const Duration(days: 1)), _location(zonaHoraria));

DateTime inicioSemanaEnZona(DateTime fecha, String zonaHoraria) =>
    _medianoche(inicioSemana(fecha), _location(zonaHoraria));

DateTime inicioMesEnZona(DateTime fecha, String zonaHoraria) =>
    _medianoche(inicioMes(fecha), _location(zonaHoraria));
