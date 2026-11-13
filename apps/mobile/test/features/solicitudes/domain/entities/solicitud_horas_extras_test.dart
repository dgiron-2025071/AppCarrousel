import 'package:carrousel_app/features/solicitudes/data/mappers/solicitud_mapper.dart';
import 'package:carrousel_app/features/solicitudes/domain/entities/solicitud_horas_extras.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EstadoSolicitud', () {
    test('interpreta el nuevo estado cancelada', () {
      expect(EstadoSolicitud.parse('cancelada'), EstadoSolicitud.cancelada);
      expect(EstadoSolicitud.cancelada.etiqueta, 'Cancelada');
    });

    test('un estado desconocido cae en pendiente', () {
      expect(EstadoSolicitud.parse('desconocido'), EstadoSolicitud.pendiente);
      expect(EstadoSolicitud.parse(null), EstadoSolicitud.pendiente);
    });
  });

  group('solicitudDesdeMapa', () {
    test('conserva la cancelación sin revisor', () {
      final solicitud = solicitudDesdeMapa({
        'id': 's1',
        'empresa_id': 'e1',
        'empleado_id': 'u1',
        'centro_costo_id': 'c1',
        'inicio': '2026-11-10T09:00:00Z',
        'fin': '2026-11-10T11:00:00Z',
        'justificacion': 'Apoyo en el parque central durante el evento',
        'estado': 'cancelada',
        'creado_en': '2026-11-10T08:00:00Z',
        'comentario_admin': null,
        'revisado_por': null,
        'revisado_en': '2026-11-10T12:00:00Z',
      });

      expect(solicitud.estado, EstadoSolicitud.cancelada);
      expect(solicitud.revisadoPor, isNull);
      expect(solicitud.comentarioAdmin, isNull);
      expect(solicitud.revisadoEn, isNotNull);
      expect(solicitud.duracion, const Duration(hours: 2));
    });
  });
}
