import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/utils/duraciones.dart';
import '../../core/widgets/estado_widgets.dart';
import '../../data/models/solicitud_horas_extras.dart';
import '../../providers/app_providers.dart';
import '../solicitudes/widgets/solicitud_card.dart';
import 'exportar_reporte.dart';
import 'invitar_usuario_page.dart';

/// Bandeja de aprobación del administrador.
///
/// Muestra solo las solicitudes de los especialistas de su subárbol. El
/// resultado se propaga por Realtime al especialista en cuanto se confirma.
class AprobacionesPage extends ConsumerWidget {
  const AprobacionesPage({super.key});

  Future<void> _revisar(
    BuildContext context,
    WidgetRef ref,
    SolicitudDetalle detalle,
    EstadoSolicitud decision,
  ) async {
    final aprobar = decision == EstadoSolicitud.aprobada;
    final comentario = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(aprobar ? 'Aprobar solicitud' : 'Rechazar solicitud'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detalle.empleadoNombre,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatearFecha(detalle.solicitud.inicio)} · '
                '${formatearHora(detalle.solicitud.inicio)} - '
                '${formatearHora(detalle.solicitud.fin)} '
                '(${formatearDuracion(detalle.solicitud.duracion)})',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(dialogo).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                detalle.solicitud.justificacion,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: comentario,
                maxLines: 3,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Comentario (opcional)',
                  hintText: aprobar
                      ? 'Puedes dejar una nota para el especialista.'
                      : 'Explica el motivo del rechazo.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            style: aprobar
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialogo).colorScheme.error,
                    foregroundColor: Theme.of(dialogo).colorScheme.onError,
                  ),
            child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );

    final texto = comentario.text;
    comentario.dispose();

    if (confirmado != true || !context.mounted) return;

    try {
      await ref.read(solicitudRepositoryProvider).revisar(
            solicitudId: detalle.solicitud.id,
            decision: decision,
            comentario: texto,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              aprobar
                  ? 'Solicitud aprobada. El especialista ya puede verlo.'
                  : 'Solicitud rechazada. El especialista ya puede verlo.',
            ),
          ),
        );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final solicitudesAsync = ref.watch(solicitudesDetalladasProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(solicitudesStreamProvider);
        await ref.read(solicitudesStreamProvider.future);
      },
      child: solicitudesAsync.when(
        loading: () =>
            const CargandoWidget(mensaje: 'Cargando solicitudes del equipo...'),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: MensajeError(
                mensaje: 'No se pudieron cargar las solicitudes de tu equipo.',
                onReintentar: () => ref.invalidate(solicitudesStreamProvider),
              ),
            ),
          ],
        ),
        data: (todas) {
          final equipo = perfil == null
              ? todas
              : todas
                  .where(
                    (detalle) => detalle.solicitud.empleadoId != perfil.id,
                  )
                  .toList(growable: false);
          final pendientes = equipo
              .where(
                (detalle) =>
                    detalle.solicitud.estado == EstadoSolicitud.pendiente,
              )
              .toList(growable: false);
          final revisadas = equipo
              .where(
                (detalle) =>
                    detalle.solicitud.estado != EstadoSolicitud.pendiente,
              )
              .toList(growable: false);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                'Aprobaciones',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                pendientes.isEmpty
                    ? 'No hay solicitudes pendientes de tu equipo.'
                    : '${pendientes.length} ${pendientes.length == 1 ? 'solicitud pendiente' : 'solicitudes pendientes'} de tu equipo.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const InvitarUsuarioPage(),
                        ),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Invitar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => exportarReporteHorasExtras(context, ref),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Reporte'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Seccion(titulo: 'Pendientes', contador: pendientes.length),
              if (pendientes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: EstadoVacio(
                    icono: Icons.task_alt_rounded,
                    titulo: 'Todo al día',
                    mensaje:
                        'Las nuevas solicitudes de tu equipo aparecerán aquí automáticamente.',
                  ),
                )
              else
                for (final detalle in pendientes)
                  SolicitudCard(
                    detalle: detalle,
                    mostrarEmpleado: true,
                    acciones: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _revisar(
                              context,
                              ref,
                              detalle,
                              EstadoSolicitud.rechazada,
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Rechazar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _revisar(
                              context,
                              ref,
                              detalle,
                              EstadoSolicitud.aprobada,
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Aprobar'),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (revisadas.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Seccion(titulo: 'Historial', contador: revisadas.length),
                const SizedBox(height: 10),
                for (final detalle in revisadas)
                  SolicitudCard(detalle: detalle, mostrarEmpleado: true),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.contador});

  final String titulo;
  final int contador;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          titulo,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colores.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$contador',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colores.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
