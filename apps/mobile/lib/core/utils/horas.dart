/// Utilidades puras de `HH:mm` compartidas por entidades, mappers y la UI.
///
/// `HH:mm:ss` también se acepta porque PostgreSQL devuelve a veces segundos en
/// columnas `time`; la app siempre guarda y muestra `HH:mm`.
String normalizarHora(String? valor) {
  final texto = (valor ?? '').trim();
  if (texto.isEmpty) return '--:--';
  final partes = texto.split(':');
  if (partes.length < 2) return '--:--';
  final hora = int.tryParse(partes[0]);
  final minuto = int.tryParse(partes[1]);
  if (hora == null || minuto == null) return '--:--';
  if (hora < 0 || hora > 23 || minuto < 0 || minuto > 59) return '--:--';
  return '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
}

/// `HH:mm` a minutos desde medianoche. Un valor inválido cuenta como 0.
int minutosDeHora(String? valor) {
  final normalizada = normalizarHora(valor);
  if (normalizada == '--:--') return 0;
  final partes = normalizada.split(':');
  return int.parse(partes[0]) * 60 + int.parse(partes[1]);
}

/// Minutos desde medianoche a `HH:mm`, ajustando vueltas de 24 h.
String horaDeMinutos(int minutos) {
  final normalizado = minutos % 1440;
  final hora = normalizado ~/ 60;
  final minuto = normalizado % 60;
  return '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
}

/// La base exige `hora_entrada <> hora_salida`. Una salida menor sí es válida:
/// representa un turno nocturno que cruza medianoche.
String? validarFranja(String entrada, String salida) {
  if (minutosDeHora(entrada) == minutosDeHora(salida)) {
    return 'La entrada y la salida no pueden ser la misma hora.';
  }
  return null;
}
