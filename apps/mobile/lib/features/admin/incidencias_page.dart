import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/duraciones.dart';
import '../../core/widgets/ecosistema.dart';
import '../../core/widgets/estado_widgets.dart';
import '../../data/models/admin_models.dart';
import '../../providers/app_providers.dart';

/// Incidencias que la base de datos detecta al marcar. El admin las resuelve
/// (justificada) o las descarta, siempre con una nota.
class IncidenciasPage extends ConsumerWidget {
  const IncidenciasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Incidencias'),
          bottom: const TabBar(tabs: [Tab(text: 'Abiertas'), Tab(text: 'Cerradas')]),
        ),
        body: const TabBarView(
          children: [_Lista(abiertas: true), _Lista(abiertas: false)],
        ),
      ),
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.abiertas});

  final bool abiertas;

  Future<void> _cerrar(
    BuildContext context,
    WidgetRef ref,
    Incidencia incidencia, {
    required bool descartar,
  }) async {
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(descartar ? 'Descartar incidencia' : 'Resolver incidencia'),
        content: TextField(
          controller: nota,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: descartar ? 'Por qué no aplica' : 'Justificación o acción tomada',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: Text(descartar ? 'Descartar' : 'Resolver'),
          ),
        ],
      ),
    );
    final texto = nota.text;
    nota.dispose();
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).cerrarIncidencia(
            id: incidencia.id,
            descartar: descartar,
            nota: texto,
          );
      ref.invalidate(incidenciasProvider);
      ref.invalidate(resumenAdminProvider);
      if (context.mounted) {
        mostrarAviso(context, 'Incidencia cerrada.', tipo: TipoAviso.success);
      }
    } catch (error) {
      if (context.mounted) {
        mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(incidenciasProvider(abiertas));
    final personas = ref.watch(personasProvider).valueOrNull ?? const {};
    final c = ColoresCarrousel.of(context);

    return datos.when(
      loading: () => const CargandoWidget(mensaje: 'Cargando incidencias...'),
      error: (_, _) => MensajeError(
        mensaje: 'No se pudieron cargar las incidencias.',
        onReintentar: () => ref.invalidate(incidenciasProvider(abiertas)),
      ),
      data: (lista) => lista.isEmpty
          ? EstadoVacio(
              icono: Icons.verified_rounded,
              titulo: abiertas ? 'Sin incidencias abiertas' : 'Sin historial',
              mensaje: abiertas
                  ? 'Tu equipo está marcando según su horario.'
                  : 'Las incidencias cerradas aparecerán aquí.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lista.length,
              itemBuilder: (_, i) {
                final inc = lista[i];
                final color = switch (inc.severidad) {
                  'alta' => c.danger,
                  'media' => c.warning,
                  _ => c.info,
                };
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: color, width: 4)),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                personas[inc.empleadoId]?.nombre ?? 'Colaborador',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              '${inc.tipo.etiqueta} · ${inc.severidad}',
                              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(inc.descripcion),
                        Text(formatearFechaHora(inc.creadoEn),
                            style: TextStyle(fontSize: 12, color: c.muted)),
                        if (!inc.abierta && inc.resolucion != null) ...[
                          const SizedBox(height: 6),
                          Text('${inc.estado == 'descartada' ? 'Descartada' : 'Resuelta'}: ${inc.resolucion}',
                              style: TextStyle(fontSize: 13, color: c.muted)),
                        ],
                        if (inc.abierta) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _cerrar(context, ref, inc, descartar: true),
                                  child: const Text('Descartar'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _cerrar(context, ref, inc, descartar: false),
                                  child: const Text('Resolver'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
