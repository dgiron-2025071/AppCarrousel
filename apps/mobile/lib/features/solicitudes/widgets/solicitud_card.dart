import 'package:flutter/material.dart';

import '../../../core/utils/duraciones.dart';
import '../../../data/models/solicitud_horas_extras.dart';

class EstadoChip extends StatelessWidget {
  const EstadoChip({super.key, required this.estado});

  final EstadoSolicitud estado;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final (Color fondo, Color texto, IconData icono) = switch (estado) {
      EstadoSolicitud.pendiente => (
          const Color(0xFFFFF3CD),
          const Color(0xFF8A6100),
          Icons.hourglass_top_rounded,
        ),
      EstadoSolicitud.aprobada => (
          const Color(0xFFD1FAE5),
          const Color(0xFF065F46),
          Icons.check_circle_rounded,
        ),
      EstadoSolicitud.rechazada => (
          colores.errorContainer,
          colores.onErrorContainer,
          Icons.cancel_rounded,
        ),
      EstadoSolicitud.cancelada => (
          colores.surfaceContainerHighest,
          colores.onSurfaceVariant,
          Icons.undo_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: texto),
          const SizedBox(width: 4),
          Text(
            estado.etiqueta,
            style: TextStyle(
              color: texto,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class SolicitudCard extends StatelessWidget {
  const SolicitudCard({
    super.key,
    required this.detalle,
    this.mostrarEmpleado = false,
    this.acciones,
  });

  final SolicitudDetalle detalle;
  final bool mostrarEmpleado;
  final Widget? acciones;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final solicitud = detalle.solicitud;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colores.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colores.outlineVariant, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 42,
                width: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colores.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  mostrarEmpleado
                      ? Icons.person_rounded
                      : Icons.attractions_rounded,
                  color: colores.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mostrarEmpleado
                          ? detalle.empleadoNombre
                          : detalle.centroNombre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mostrarEmpleado
                          ? detalle.centroNombre
                          : formatearFecha(solicitud.inicio),
                      style: TextStyle(
                        fontSize: 12,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              EstadoChip(estado: solicitud.estado),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colores.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: colores.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${formatearFecha(solicitud.inicio)} · '
                    '${formatearHora(solicitud.inicio)} - '
                    '${formatearHora(solicitud.fin)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  formatearDuracion(solicitud.duracion),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colores.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Justificación',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: colores.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(solicitud.justificacion),
          if (solicitud.comentarioAdmin != null &&
              solicitud.comentarioAdmin!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: solicitud.estado == EstadoSolicitud.rechazada
                    ? colores.errorContainer
                    : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comentario del administrador',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: solicitud.estado == EstadoSolicitud.rechazada
                          ? colores.onErrorContainer
                          : const Color(0xFF065F46),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    solicitud.comentarioAdmin!,
                    style: TextStyle(
                      color: solicitud.estado == EstadoSolicitud.rechazada
                          ? colores.onErrorContainer
                          : const Color(0xFF065F46),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (solicitud.estado != EstadoSolicitud.pendiente &&
              solicitud.revisadoEn != null) ...[
            const SizedBox(height: 10),
            Text(
              solicitud.estado == EstadoSolicitud.cancelada
                  ? 'Retirada ${formatearFechaHora(solicitud.revisadoEn!)}'
                  : 'Revisada ${formatearFechaHora(solicitud.revisadoEn!)}',
              style: TextStyle(
                fontSize: 11,
                color: colores.onSurfaceVariant,
              ),
            ),
          ],
          if (acciones != null) ...[
            const SizedBox(height: 14),
            acciones!,
          ],
        ],
      ),
    );
  }
}
