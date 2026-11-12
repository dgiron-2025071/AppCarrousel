import 'package:carrousel_app/core/utils/reporte_csv.dart';
import 'package:carrousel_app/data/models/fila_reporte_horas_extras.dart';
import 'package:carrousel_app/data/models/solicitud_horas_extras.dart';
import 'package:flutter_test/flutter_test.dart';

FilaReporteHorasExtras _fila({
  String actividad = 'Cambio de bandas en la rueda',
  EstadoSolicitud estado = EstadoSolicitud.aprobada,
  double horas = 2.5,
}) =>
    FilaReporteHorasExtras(
      id: 's1',
      empleado: 'Francisco Choc',
      puesto: 'Técnico',
      inicio: DateTime(2026, 11, 10, 18),
      fin: DateTime(2026, 11, 10, 20, 30),
      horas: horas,
      actividadRealizada: actividad,
      cecoCodigo: '057.01',
      cecoNombre: 'Andaria Kiddies',
      personaQueAutoriza: 'Jefe de Mantenimiento',
      estado: estado,
      creadoEn: DateTime(2026, 11, 10, 21, 5),
      revisadoPor: 'Jefe de Mantenimiento',
      revisadoEn: DateTime(2026, 11, 11, 8),
    );

void main() {
  test('el encabezado sigue el orden del formulario actual', () {
    final csv = generarCsvHorasExtras(const []);
    expect(
      csv.startsWith(
        '\uFEFFMarca temporal,Nombre del técnico,Puesto,'
        'Fecha de actividad',
      ),
      isTrue,
    );
    expect(
      csv,
      contains(
        'Cantidad de horas Extras,Código centro de costo,'
        'Centro de costo,Persona que autoriza',
      ),
    );
  });

  test('escribe una fila con fecha, horas y centro de costo', () {
    final lineas = generarCsvHorasExtras([_fila()]).split('\r\n');
    expect(
      lineas[1],
      '10/11/2026 21:05,Francisco Choc,Técnico,10/11/2026,18:00,20:30,'
      'Cambio de bandas en la rueda,2.5,057.01,Andaria Kiddies,'
      'Jefe de Mantenimiento,Aprobada,Jefe de Mantenimiento,11/11/2026 08:00,',
    );
  });

  test('escapa comas, comillas, saltos de línea y fórmulas', () {
    final csv = generarCsvHorasExtras([
      _fila(actividad: 'Revisé motor, "banda"\ny frenos'),
      _fila(actividad: '=HYPERLINK("x")'),
    ]);
    expect(csv, contains('"Revisé motor, ""banda""\ny frenos"'));
    expect(csv, contains('"\'=HYPERLINK(""x"")"'));
  });

  test('suma solo las horas aprobadas', () {
    expect(
      horasAprobadas([
        _fila(horas: 2),
        _fila(horas: 1.5),
        _fila(horas: 4, estado: EstadoSolicitud.pendiente),
      ]),
      3.5,
    );
  });
}
