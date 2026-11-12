import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/utils/duraciones.dart';
import '../../core/utils/parques.dart';
import '../../core/widgets/estado_widgets.dart';
import '../../data/models/horario.dart';
import '../../data/models/parque.dart';
import '../../providers/app_providers.dart';

/// Horario semanal personalizado de un empleado: qué días trabaja, a qué
/// hora entra y sale, en qué parque y cuánta tolerancia tiene.
class HorarioEmpleadoPage extends ConsumerStatefulWidget {
  const HorarioEmpleadoPage({
    super.key,
    required this.empleadoId,
    required this.nombre,
  });

  final String empleadoId;
  final String nombre;

  @override
  ConsumerState<HorarioEmpleadoPage> createState() =>
      _HorarioEmpleadoPageState();
}

class _HorarioEmpleadoPageState extends ConsumerState<HorarioEmpleadoPage> {
  Map<int, Horario>? _semana;
  List<Horario> _anteriores = const [];
  bool _guardando = false;

  void _cargar(List<Horario> horarios) {
    _anteriores = horarios;
    _semana = {for (final h in horarios) h.diaSemana: h};
  }

  void _activar(int dia, bool activo) {
    setState(() {
      if (!activo) {
        _semana!.remove(dia);
        return;
      }
      // Copia el día trabajado más cercano para no reescribir todo.
      final base = _semana!.values.isEmpty ? null : _semana!.values.first;
      _semana![dia] = Horario(
        diaSemana: dia,
        horaEntrada: base?.horaEntrada ?? const TimeOfDay(hour: 8, minute: 0),
        horaSalida: base?.horaSalida ?? const TimeOfDay(hour: 17, minute: 0),
        parqueId: base?.parqueId,
        toleranciaMinutos: base?.toleranciaMinutos ?? 10,
      );
    });
  }

  Future<void> _elegirHora(int dia, {required bool entrada}) async {
    final actual = _semana![dia]!;
    final hora = await showTimePicker(
      context: context,
      initialTime: entrada ? actual.horaEntrada : actual.horaSalida,
      helpText: entrada ? 'Hora de entrada' : 'Hora de salida',
    );
    if (hora == null || !mounted) return;
    final nuevo = entrada
        ? actual.copyWith(horaEntrada: hora)
        : actual.copyWith(horaSalida: hora);
    if (nuevo.horaEntrada == nuevo.horaSalida) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('La entrada y la salida no pueden ser iguales.')),
      );
      return;
    }
    setState(() => _semana![dia] = nuevo);
  }

  void _copiarATodos(int dia) {
    final origen = _semana![dia]!;
    setState(() {
      for (final otro in _semana!.keys.toList()) {
        _semana![otro] = Horario(
          id: _semana![otro]!.id,
          diaSemana: otro,
          horaEntrada: origen.horaEntrada,
          horaSalida: origen.horaSalida,
          parqueId: origen.parqueId,
          toleranciaMinutos: origen.toleranciaMinutos,
        );
      }
    });
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await ref.read(horarioRepositoryProvider).guardarSemana(
            empleadoId: widget.empleadoId,
            anteriores: _anteriores,
            semana: _semana!,
          );
      ref.invalidate(horariosDeProvider(widget.empleadoId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Horario de ${widget.nombre} guardado.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeDeError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final horariosAsync = ref.watch(horariosDeProvider(widget.empleadoId));
    final parques = parquesParaEntrada(
      ref.watch(parquesProvider).valueOrNull ?? const <Parque>[],
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre)),
      body: horariosAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando horario...'),
        error: (_, _) => MensajeError(
          mensaje: 'No se pudo cargar el horario.',
          onReintentar: () =>
              ref.invalidate(horariosDeProvider(widget.empleadoId)),
        ),
        data: (horarios) {
          if (_semana == null) _cargar(horarios);
          final semana = _semana!;
          final totalSemana = semana.values.fold<Duration>(
            Duration.zero,
            (total, h) => total + h.duracion,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Text(
                'Total programado: ${formatearDuracion(totalSemana)} por semana',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (var dia = 1; dia <= 7; dia++)
                _DiaCard(
                  dia: dia,
                  horario: semana[dia],
                  parques: parques,
                  onActivar: (activo) => _activar(dia, activo),
                  onEntrada: () => _elegirHora(dia, entrada: true),
                  onSalida: () => _elegirHora(dia, entrada: false),
                  onParque: (id) => setState(() => semana[dia] = id == null
                      ? semana[dia]!.copyWith(quitarParque: true)
                      : semana[dia]!.copyWith(parqueId: id)),
                  onTolerancia: (minutos) => setState(() => semana[dia] =
                      semana[dia]!.copyWith(toleranciaMinutos: minutos)),
                  onCopiar: () => _copiarATodos(dia),
                ),
            ],
          );
        },
      ),
      floatingActionButton: _semana == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Guardar horario'),
            ),
    );
  }
}

class _DiaCard extends StatelessWidget {
  const _DiaCard({
    required this.dia,
    required this.horario,
    required this.parques,
    required this.onActivar,
    required this.onEntrada,
    required this.onSalida,
    required this.onParque,
    required this.onTolerancia,
    required this.onCopiar,
  });

  final int dia;
  final Horario? horario;
  final List<Parque> parques;
  final ValueChanged<bool> onActivar;
  final VoidCallback onEntrada;
  final VoidCallback onSalida;
  final ValueChanged<String?> onParque;
  final ValueChanged<int> onTolerancia;
  final VoidCallback onCopiar;

  String _hora(TimeOfDay hora) => horaSql(hora);

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final h = horario;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    nombreDia(dia),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (h != null)
                  IconButton(
                    tooltip: 'Copiar a los demás días',
                    onPressed: onCopiar,
                    icon: const Icon(Icons.copy_all_rounded),
                  ),
                Switch(value: h != null, onChanged: onActivar),
              ],
            ),
            if (h == null)
              Text('Descanso',
                  style: TextStyle(color: colores.onSurfaceVariant))
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEntrada,
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: Text('Entra ${_hora(h.horaEntrada)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSalida,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: Text('Sale ${_hora(h.horaSalida)}'),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
              if (h.nocturno)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Turno nocturno: sale al día siguiente.',
                    style: TextStyle(fontSize: 12, color: colores.primary),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('parque-$dia-${h.parqueId}'),
                      initialValue: parques.any((p) => p.id == h.parqueId)
                          ? h.parqueId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Parque',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Cualquiera'),
                        ),
                        for (final parque in parques)
                          DropdownMenuItem(
                            value: parque.id,
                            child: Text(
                              parque.nombre,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: onParque,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('tolerancia-$dia-${h.toleranciaMinutos}'),
                      initialValue: h.toleranciaMinutos,
                      decoration: const InputDecoration(
                        labelText: 'Tolerancia',
                        isDense: true,
                      ),
                      items: [
                        for (final minutos in {
                          0,
                          5,
                          10,
                          15,
                          30,
                          h.toleranciaMinutos
                        })
                          DropdownMenuItem(
                            value: minutos,
                            child: Text('$minutos min'),
                          ),
                      ],
                      onChanged: (valor) {
                        if (valor != null) onTolerancia(valor);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
