import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/duraciones.dart';
import '../../../core/utils/horas_extra.dart';
import '../../../data/models/horario.dart';
import '../../../data/models/parque.dart';
import '../../../providers/app_providers.dart';
import '../../solicitudes/solicitud_form_page.dart';

/// "Hoy: 08:00 – 17:00 · Parque X", o el día de descanso.
class HorarioHoyCard extends ConsumerWidget {
  const HorarioHoyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final horarios = ref.watch(horariosDeProvider(user.id)).valueOrNull;
    if (horarios == null || horarios.isEmpty) return const SizedBox.shrink();

    final hoy = DateTime.now().weekday;
    Horario? deHoy;
    for (final horario in horarios) {
      if (horario.diaSemana == hoy) deHoy = horario;
    }
    final parques = ref.watch(parquesProvider).valueOrNull ?? const <Parque>[];
    String? parque;
    for (final p in parques) {
      if (p.id == deHoy?.parqueId) parque = p.nombre;
    }

    final colores = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colores.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_rounded, color: colores.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              deHoy == null
                  ? 'Hoy descansas según tu horario.'
                  : 'Hoy: ${horaSql(deHoy.horaEntrada)} – '
                      '${horaSql(deHoy.horaSalida)}'
                      '${parque == null ? '' : ' · $parque'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiempo trabajado después del horario, respaldado por la geocerca, que
/// todavía no se ha solicitado. Un toque abre el formulario ya lleno.
class HorasExtraDetectadasCard extends ConsumerWidget {
  const HorasExtraDetectadasCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detectadas =
        ref.watch(horasExtraPorSolicitarProvider).valueOrNull ?? const [];
    if (detectadas.isEmpty) return const SizedBox.shrink();
    final parques = {
      for (final p
          in ref.watch(parquesProvider).valueOrNull ?? const <Parque>[])
        p.id: p,
    };
    final colores = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colores.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gps_fixed_rounded, color: colores.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Horas extra detectadas por GPS',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colores.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Saliste después de tu horario y dentro del parque.',
            style: TextStyle(fontSize: 12, color: colores.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          for (final fila in detectadas.take(3))
            _FilaDetectada(
              fila: fila,
              parque: parques[fila.parqueId],
              onSolicitar: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SolicitudFormPage(
                      precargada: SolicitudPrecargada(
                        jornadaId: fila.jornadaId,
                        inicio: inicioDelExtra(fila),
                        cantidad: extraRedondeado(fila.minutosExtra!),
                        parqueId: fila.parqueId,
                      ),
                    ),
                  ),
                );
                ref.invalidate(horasExtraPorSolicitarProvider);
              },
            ),
        ],
      ),
    );
  }
}

class _FilaDetectada extends StatelessWidget {
  const _FilaDetectada({
    required this.fila,
    required this.parque,
    required this.onSolicitar,
  });

  final CumplimientoJornada fila;
  final Parque? parque;
  final VoidCallback onSolicitar;

  @override
  Widget build(BuildContext context) {
    final extra = extraRedondeado(fila.minutosExtra!);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatearFecha(fila.entradaEn)} · ${formatearDuracion(extra)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Salida programada ${formatearHora(fila.salidaProgramada!)}, '
                  'marcaste ${formatearHora(fila.salidaEn!)}'
                  '${parque == null ? '' : ' en ${parque!.nombre}'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // El tema pide ancho completo (Size.fromHeight); dentro de una
          // fila hay que darle un ancho mínimo finito.
          FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: onSolicitar,
            child: const Text('Solicitar'),
          ),
        ],
      ),
    );
  }
}
