import 'package:carrousel_app/features/horario/domain/entities/horario.dart';
import 'package:carrousel_app/features/horario/domain/utils/horarios.dart';
import 'package:flutter_test/flutter_test.dart';

Horario horario({
  int dia = 1,
  String entrada = '09:00',
  String salida = '18:00',
  int toleranciaEntrada = 10,
  int toleranciaSalida = 10,
}) {
  return Horario(
    id: 'h1',
    empresaId: 'e1',
    empleadoId: 'u1',
    diaSemana: dia,
    horaEntrada: entrada,
    horaSalida: salida,
    toleranciaEntradaMin: toleranciaEntrada,
    toleranciaSalidaMin: toleranciaSalida,
    activo: true,
  );
}

void main() {
  group('nombreDia', () {
    test('mapea los días ISO a español', () {
      expect(nombreDia(1), 'Lunes');
      expect(nombreDia(7), 'Domingo');
    });

    test('un día fuera de rango no rompe la etiqueta', () {
      expect(nombreDia(0), 'Día 0');
      expect(nombreDia(9), 'Día 9');
    });
  });

  group('normalizarHora', () {
    test('recorta segundos y rellena con ceros', () {
      expect(normalizarHora('9:5:00'), '09:05');
      expect(normalizarHora('23:59:59'), '23:59');
    });

    test('descarta valores inválidos', () {
      expect(normalizarHora(null), '--:--');
      expect(normalizarHora('24:00'), '--:--');
      expect(normalizarHora('sin hora'), '--:--');
    });
  });

  group('minutos y formato', () {
    test('convierte entre minutos y HH:mm', () {
      expect(minutosDeHora('01:30'), 90);
      expect(horaDeMinutos(90), '01:30');
      expect(horaDeMinutos(1440), '00:00');
    });

    test('una hora inválida equivale a cero minutos', () {
      expect(minutosDeHora('--:--'), 0);
    });
  });

  group('turnos', () {
    test('un turno normal dura la diferencia', () {
      final turno = horario();
      expect(turno.nocturno, isFalse);
      expect(turno.duracionMinutos, 9 * 60);
      expect(duracionTurno(turno), '9 h');
      expect(describirTurno(turno), '09:00 - 18:00');
    });

    test('un turno nocturno cruza medianoche', () {
      final turno = horario(entrada: '22:00', salida: '06:00');
      expect(turno.nocturno, isTrue);
      expect(turno.duracionMinutos, 8 * 60);
      expect(describirTurno(turno), '22:00 - 06:00 (+1 día)');
    });

    test('incluye minutos sueltos en la duración', () {
      final turno = horario(entrada: '08:15', salida: '17:45');
      expect(duracionTurno(turno), '9 h 30 min');
    });

    test('la base rechaza entrada y salida iguales', () {
      final turno = horario(entrada: '09:00', salida: '09:00');
      expect(turno.franjaValida, isFalse);
      expect(turno.nocturno, isFalse);
      expect(validarFranja(turno.horaEntrada, turno.horaSalida), isNotNull);
      expect(horario(entrada: '22:00', salida: '06:00').franjaValida, isTrue);
    });
  });
}
