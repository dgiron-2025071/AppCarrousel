import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/duraciones.dart';
import '../../core/widgets/ecosistema.dart';
import '../../core/widgets/estado_widgets.dart';
import '../../data/models/jornada.dart';
import '../../providers/app_providers.dart';

/// Jornadas del equipo (14 días). Una jornada cerrada se puede ajustar con
/// motivo; el ajuste queda en el historial y el empleado lo ve.
class JornadasEquipoPage extends ConsumerWidget {
  const JornadasEquipoPage({super.key});

  Future<void> _ajustar(BuildContext context, WidgetRef ref, Jornada jornada, String nombre) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaAjuste(jornada: jornada, nombre: nombre),
    );
    if (ok == true && context.mounted) {
      ref.invalidate(jornadasEquipoProvider);
      mostrarAviso(context, 'Jornada ajustada.', tipo: TipoAviso.success);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(jornadasEquipoProvider);
    final personas = ref.watch(personasProvider).valueOrNull ?? const {};
    final parques = {
      for (final p in ref.watch(parquesProvider).valueOrNull ?? const []) p.id: p.nombre,
    };
    final c = ColoresCarrousel.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Jornadas del equipo'), bottom: const FranjaMarca()),
      body: datos.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando jornadas...'),
        error: (_, _) => MensajeError(
          mensaje: 'No se pudieron cargar las jornadas.',
          onReintentar: () => ref.invalidate(jornadasEquipoProvider),
        ),
        data: (jornadas) => jornadas.isEmpty
            ? const EstadoVacio(
                icono: Icons.event_busy_rounded,
                titulo: 'Sin jornadas',
                mensaje: 'Tu equipo no ha marcado en los últimos 14 días.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(jornadasEquipoProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: jornadas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final j = jornadas[i];
                    final nombre = personas[j.empleadoId]?.nombre ?? 'Colaborador';
                    final abierta = j.salidaEn == null;
                    return ListTile(
                      leading: Icon(
                        abierta ? Icons.radio_button_checked_rounded : Icons.check_circle_outline_rounded,
                        color: abierta ? c.success : c.muted,
                      ),
                      title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${parques[j.parqueId] ?? 'Parque'} · ${formatearFecha(j.entradaEn)} '
                        '${formatearHora(j.entradaEn)} – '
                        '${abierta ? 'en turno' : formatearHora(j.salidaEn!)}',
                      ),
                      trailing: abierta
                          ? null
                          : TextButton(
                              onPressed: () => _ajustar(context, ref, j, nombre),
                              child: const Text('Ajustar'),
                            ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _HojaAjuste extends ConsumerStatefulWidget {
  const _HojaAjuste({required this.jornada, required this.nombre});

  final Jornada jornada;
  final String nombre;

  @override
  ConsumerState<_HojaAjuste> createState() => _HojaAjusteState();
}

class _HojaAjusteState extends ConsumerState<_HojaAjuste> {
  late DateTime _entrada = widget.jornada.entradaEn;
  late DateTime _salida = widget.jornada.salidaEn!;
  final _motivo = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<DateTime?> _elegir(DateTime actual) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: actual.subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (fecha == null || !mounted) return null;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(actual));
    if (hora == null) return null;
    return DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
  }

  Future<void> _guardar() async {
    if (!_salida.isAfter(_entrada)) {
      mostrarAviso(context, 'La salida debe ser posterior a la entrada.', tipo: TipoAviso.warning);
      return;
    }
    if (_motivo.text.trim().length < 10) {
      mostrarAviso(context, 'Explica el motivo (mínimo 10 caracteres).', tipo: TipoAviso.warning);
      return;
    }
    if (!await confirmar(
      context,
      pregunta: '¿Ajustar la jornada de ${widget.nombre}?',
      detalle: 'Quedará registrado quién la ajustó y por qué.',
      aceptar: 'Ajustar',
    )) {
      return;
    }
    setState(() => _guardando = true);
    try {
      await ref.read(adminRepositoryProvider).ajustarJornada(
            jornadaId: widget.jornada.id,
            entrada: _entrada,
            salida: _salida,
            motivo: _motivo.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EncabezadoPagina(eyebrow: 'Ajuste de jornada', titulo: widget.nombre),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final v = await _elegir(_entrada);
                      if (v != null) setState(() => _entrada = v);
                    },
                    child: Text('Entrada\n${formatearFechaHora(_entrada)}', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final v = await _elegir(_salida);
                      if (v != null) setState(() => _salida = v);
                    },
                    child: Text('Salida\n${formatearFechaHora(_salida)}', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivo,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Motivo del ajuste'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: const Text('Guardar ajuste'),
            ),
          ],
        ),
      ),
    );
  }
}
