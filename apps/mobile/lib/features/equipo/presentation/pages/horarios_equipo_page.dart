import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/core/utils/selectores_fecha.dart';
import 'package:carrousel_app/core/widgets/estado_widgets.dart';
import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/equipo/domain/entities/miembro_equipo.dart';
import 'package:carrousel_app/features/equipo/presentation/providers/equipo_providers.dart';
import 'package:carrousel_app/features/horario/domain/entities/horario.dart';
import 'package:carrousel_app/features/horario/domain/utils/horarios.dart';
import 'package:carrousel_app/features/horario/presentation/providers/horario_providers.dart';

/// Editor del horario semanal de cada integrante del equipo.
class HorariosEquipoPage extends ConsumerStatefulWidget {
  const HorariosEquipoPage({super.key});

  @override
  ConsumerState<HorariosEquipoPage> createState() => _HorariosEquipoPageState();
}

class _HorariosEquipoPageState extends ConsumerState<HorariosEquipoPage> {
  String? _empleadoId;

  Future<void> _editar({
    required Perfil? perfil,
    required MiembroEquipo miembro,
    required int diaSemana,
    Horario? horario,
  }) async {
    if (perfil == null) return;

    final edicion = await showDialog<_EdicionHorario>(
      context: context,
      builder: (_) => _DialogoHorario(
        miembro: miembro,
        diaSemana: diaSemana,
        horario: horario,
      ),
    );
    if (edicion == null || !mounted) return;

    try {
      await ref.read(guardarHorarioProvider)(
        empresaId: perfil.empresaId,
        empleadoId: miembro.id,
        diaSemana: diaSemana,
        horaEntrada: edicion.horaEntrada,
        horaSalida: edicion.horaSalida,
        toleranciaEntradaMin: edicion.toleranciaEntrada,
        toleranciaSalidaMin: edicion.toleranciaSalida,
        horarioId: horario?.id,
      );
      ref.invalidate(horariosEmpleadoProvider(miembro.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              horario == null
                  ? 'Horario de ${nombreDia(diaSemana)} agregado.'
                  : 'Horario de ${nombreDia(diaSemana)} actualizado.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }

  Future<void> _eliminar(MiembroEquipo miembro, Horario horario) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Eliminar horario'),
        content: Text(
          '¿Quitar el horario del ${nombreDia(horario.diaSemana).toLowerCase()} '
          'de ${miembro.nombreCompleto}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogo).colorScheme.error,
              foregroundColor: Theme.of(dialogo).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    try {
      await ref.read(eliminarHorarioProvider)(horario.id);
      ref.invalidate(horariosEmpleadoProvider(miembro.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Horario eliminado.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final miembrosAsync = ref.watch(miembrosEquipoProvider);
    final perfil = ref.watch(perfilProvider).valueOrNull;

    return miembrosAsync.when(
      loading: () => const CargandoWidget(mensaje: 'Cargando el equipo...'),
      error: (error, _) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: MensajeError(
              mensaje: 'No se pudo cargar el equipo.',
              onReintentar: () => ref.invalidate(miembrosEquipoProvider),
            ),
          ),
        ],
      ),
      data: (miembros) {
        final activos = miembros
            .where((miembro) => miembro.activo)
            .toList(growable: false);
        if (activos.isEmpty) {
          return const EstadoVacio(
            icono: Icons.groups_outlined,
            titulo: 'Sin integrantes',
            mensaje: 'Aprueba un alta para poder asignar horarios.',
          );
        }
        final seleccionado = activos.firstWhere(
          (miembro) => miembro.id == _empleadoId,
          orElse: () => activos.first,
        );
        final horariosAsync = ref.watch(
          horariosEmpleadoProvider(seleccionado.id),
        );

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Text(
              'Horarios del equipo',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Define la franja semanal y la tolerancia con la que se evalúan '
              'las incidencias de entrada y salida.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: seleccionado.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Integrante',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              items: [
                for (final miembro in activos)
                  DropdownMenuItem(
                    value: miembro.id,
                    child: Text(
                      '${miembro.nombreCompleto} · ${miembro.rolEtiqueta}',
                    ),
                  ),
              ],
              onChanged: (valor) => setState(() => _empleadoId = valor),
            ),
            const SizedBox(height: 16),
            horariosAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: MensajeError(
                  mensaje: 'No se pudo cargar el horario.',
                  onReintentar: () =>
                      ref.invalidate(horariosEmpleadoProvider(seleccionado.id)),
                ),
              ),
              data: (horarios) {
                final porDia = {
                  for (final horario in horarios) horario.diaSemana: horario,
                };
                return Column(
                  children: [
                    for (var dia = 1; dia <= 7; dia++)
                      _FilaHorario(
                        dia: dia,
                        horario: porDia[dia],
                        onEditar: () => _editar(
                          perfil: perfil,
                          miembro: seleccionado,
                          diaSemana: dia,
                          horario: porDia[dia],
                        ),
                        onEliminar: porDia[dia] == null
                            ? null
                            : () => _eliminar(seleccionado, porDia[dia]!),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _FilaHorario extends StatelessWidget {
  const _FilaHorario({
    required this.dia,
    required this.horario,
    required this.onEditar,
    required this.onEliminar,
  });

  final int dia;
  final Horario? horario;
  final VoidCallback onEditar;
  final VoidCallback? onEliminar;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final actual = horario;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: colores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.outlineVariant, width: 0.7),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      nombreDia(dia),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (actual?.nocturno ?? false) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colores.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Nocturno',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colores.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  actual == null
                      ? 'Descanso'
                      : '${describirTurno(actual)} · ${duracionTurno(actual)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colores.onSurfaceVariant,
                  ),
                ),
                if (actual != null)
                  Text(
                    'Tolerancia ${actual.toleranciaEntradaMin} min al entrar y '
                    '${actual.toleranciaSalidaMin} min al salir',
                    style: TextStyle(
                      fontSize: 11,
                      color: colores.onSurfaceVariant.withAlpha(210),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEditar,
            tooltip: actual == null ? 'Agregar horario' : 'Editar horario',
            icon: Icon(
              actual == null
                  ? Icons.add_circle_outline_rounded
                  : Icons.edit_outlined,
              color: colores.primary,
            ),
          ),
          if (onEliminar != null)
            IconButton(
              onPressed: onEliminar,
              tooltip: 'Eliminar horario',
              icon: Icon(Icons.delete_outline_rounded, color: colores.error),
            ),
        ],
      ),
    );
  }
}

class _EdicionHorario {
  const _EdicionHorario({
    required this.horaEntrada,
    required this.horaSalida,
    required this.toleranciaEntrada,
    required this.toleranciaSalida,
  });

  final String horaEntrada;
  final String horaSalida;
  final int toleranciaEntrada;
  final int toleranciaSalida;
}

class _DialogoHorario extends StatefulWidget {
  const _DialogoHorario({
    required this.miembro,
    required this.diaSemana,
    required this.horario,
  });

  final MiembroEquipo miembro;
  final int diaSemana;
  final Horario? horario;

  @override
  State<_DialogoHorario> createState() => _DialogoHorarioState();
}

class _DialogoHorarioState extends State<_DialogoHorario> {
  late String _entrada;
  late String _salida;
  late final TextEditingController _toleranciaEntrada;
  late final TextEditingController _toleranciaSalida;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entrada = widget.horario?.horaEntrada ?? '09:00';
    _salida = widget.horario?.horaSalida ?? '18:00';
    _toleranciaEntrada = TextEditingController(
      text: '${widget.horario?.toleranciaEntradaMin ?? 10}',
    );
    _toleranciaSalida = TextEditingController(
      text: '${widget.horario?.toleranciaSalidaMin ?? 10}',
    );
  }

  @override
  void dispose() {
    _toleranciaEntrada.dispose();
    _toleranciaSalida.dispose();
    super.dispose();
  }

  Future<void> _elegir({required bool entrada}) async {
    final valor = await elegirHoraTexto(
      context,
      entrada ? _entrada : _salida,
      ayuda: entrada ? 'Hora de entrada' : 'Hora de salida',
    );
    if (valor == null || !mounted) return;
    setState(() {
      if (entrada) {
        _entrada = valor;
      } else {
        _salida = valor;
      }
    });
  }

  void _confirmar() {
    // PostgreSQL exige franjas distintas; una salida menor sigue siendo un
    // turno nocturno válido.
    final franjaInvalida = validarFranja(_entrada, _salida);
    if (franjaInvalida != null) {
      setState(() => _error = franjaInvalida);
      return;
    }
    final toleranciaEntrada = int.tryParse(_toleranciaEntrada.text.trim());
    final toleranciaSalida = int.tryParse(_toleranciaSalida.text.trim());
    // La base acepta 0..240 minutos (migración 0024); el cliente no debe
    // rechazar valores que PostgreSQL considera válidos.
    if (toleranciaEntrada == null ||
        toleranciaEntrada < 0 ||
        toleranciaEntrada > 240) {
      setState(
        () => _error = 'La tolerancia de entrada debe estar entre 0 y 240.',
      );
      return;
    }
    if (toleranciaSalida == null ||
        toleranciaSalida < 0 ||
        toleranciaSalida > 240) {
      setState(
        () => _error = 'La tolerancia de salida debe estar entre 0 y 240.',
      );
      return;
    }
    Navigator.of(context).pop(
      _EdicionHorario(
        horaEntrada: _entrada,
        horaSalida: _salida,
        toleranciaEntrada: toleranciaEntrada,
        toleranciaSalida: toleranciaSalida,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${widget.horario == null ? 'Agregar' : 'Editar'} '
        '${nombreDia(widget.diaSemana).toLowerCase()}',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.miembro.nombreCompleto,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _elegir(entrada: true),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text('Entrada $_entrada'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _elegir(entrada: false),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text('Salida $_salida'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _toleranciaEntrada,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tolerancia entrada (min)',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _toleranciaSalida,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tolerancia salida (min)',
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Si la salida es menor o igual a la entrada, el turno cruza '
              'medianoche y se cierra al día siguiente.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Guardar')),
      ],
    );
  }
}
