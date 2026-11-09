import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/estado_widgets.dart';
import '../../data/models/solicitud_horas_extras.dart';
import '../../providers/app_providers.dart';
import 'solicitud_form_page.dart';
import 'widgets/solicitud_card.dart';

class SolicitudesPage extends ConsumerStatefulWidget {
  const SolicitudesPage({super.key});

  @override
  ConsumerState<SolicitudesPage> createState() => _SolicitudesPageState();
}

class _SolicitudesPageState extends ConsumerState<SolicitudesPage> {
  EstadoSolicitud? _filtro;

  Future<void> _nuevaSolicitud() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SolicitudFormPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final solicitudesAsync = ref.watch(solicitudesDetalladasProvider);

    return Scaffold(
      body: solicitudesAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando solicitudes...'),
        error: (error, _) => MensajeError(
          mensaje: 'No se pudieron cargar tus solicitudes.',
          onReintentar: () => ref.invalidate(solicitudesStreamProvider),
        ),
        data: (todas) {
          final propias = perfil == null
              ? todas
              : todas
                  .where((detalle) =>
                      detalle.solicitud.empleadoId == perfil.id)
                  .toList(growable: false);
          final visibles = _filtro == null
              ? propias
              : propias
                  .where((detalle) => detalle.solicitud.estado == _filtro)
                  .toList(growable: false);
          final pendientes = propias
              .where(
                (detalle) =>
                    detalle.solicitud.estado == EstadoSolicitud.pendiente,
              )
              .length;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(solicitudesStreamProvider);
              await ref.read(solicitudesStreamProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text(
                  'Tus horas extras',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  pendientes == 0
                      ? 'Envía el apoyo que realizaste en otro parque y consulta el resultado.'
                      : '$pendientes ${pendientes == 1 ? 'solicitud pendiente' : 'solicitudes pendientes'} de revisión.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _nuevaSolicitud,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nueva solicitud'),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Filtro(
                        etiqueta: 'Todas',
                        seleccionado: _filtro == null,
                        onTap: () => setState(() => _filtro = null),
                      ),
                      for (final estado in EstadoSolicitud.values)
                        _Filtro(
                          etiqueta: estado.etiqueta,
                          seleccionado: _filtro == estado,
                          onTap: () => setState(() => _filtro = estado),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (visibles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EstadoVacio(
                      icono: Icons.more_time_outlined,
                      titulo: _filtro == null
                          ? 'Aún no tienes solicitudes'
                          : 'Sin solicitudes ${_filtro!.etiqueta.toLowerCase()}s',
                      mensaje: _filtro == null
                          ? 'Cuando envíes horas extras verás aquí su estado en tiempo real.'
                          : 'Prueba con otro filtro para ver tu historial.',
                    ),
                  )
                else
                  for (final detalle in visibles)
                    SolicitudCard(detalle: detalle),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Filtro extends StatelessWidget {
  const _Filtro({
    required this.etiqueta,
    required this.seleccionado,
    required this.onTap,
  });

  final String etiqueta;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(etiqueta),
        selected: seleccionado,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: colores.primaryContainer,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: seleccionado
              ? colores.onPrimaryContainer
              : colores.onSurfaceVariant,
        ),
      ),
    );
  }
}
