import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/utils/centros.dart';
import '../../core/utils/duraciones.dart';
import '../../core/utils/parques.dart';
import '../../data/models/centro_costo.dart';
import '../../data/models/horario.dart';
import '../../data/models/parque.dart';
import '../../providers/app_providers.dart';

/// Cantidades de horas que se ofrecen, en medias horas (0.5 a 12).
final opcionesDeHoras = [for (var i = 1; i <= 24; i++) i * 30]
    .map((minutos) => Duration(minutes: minutos))
    .toList(growable: false);

/// Datos que llegan de una jornada GPS con tiempo extra detectado.
class SolicitudPrecargada {
  const SolicitudPrecargada({
    required this.jornadaId,
    required this.inicio,
    required this.cantidad,
    this.parqueId,
  });

  final String jornadaId;
  final DateTime inicio;
  final Duration cantidad;

  /// Lugar donde marcó; el centro de costo arranca en el del lugar.
  final String? parqueId;
}

/// Formulario de horas extras.
///
/// Sigue el orden del formulario que se usa hoy ("Formato de horas Extras"):
/// fecha de actividad, actividad realizada, cantidad de horas y centro de
/// costo. La persona que autoriza ya no se escribe: la calcula la base de
/// datos desde la jerarquía y aquí solo se muestra.
class SolicitudFormPage extends ConsumerStatefulWidget {
  const SolicitudFormPage({super.key, this.precargada});

  /// Si viene de una jornada GPS, fecha, hora, cantidad y CECO ya están
  /// llenos y la solicitud queda respaldada por esa jornada.
  final SolicitudPrecargada? precargada;

  @override
  ConsumerState<SolicitudFormPage> createState() => _SolicitudFormPageState();
}

class _SolicitudFormPageState extends ConsumerState<SolicitudFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _actividad = TextEditingController();

  late DateTime _fecha;
  late TimeOfDay _horaInicio;
  Duration _cantidad = const Duration(hours: 2);
  String? _lugarId;
  String? _centroId;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    final precargada = widget.precargada;
    if (precargada != null) {
      _fecha = inicioDelDia(precargada.inicio);
      _horaInicio = TimeOfDay.fromDateTime(precargada.inicio);
      _cantidad = opcionesDeHoras.contains(precargada.cantidad)
          ? precargada.cantidad
          : opcionesDeHoras.last;
      _lugarId = precargada.parqueId;
      return;
    }
    final ahora = DateTime.now();
    _fecha = inicioDelDia(ahora);
    _horaInicio = TimeOfDay(hour: (ahora.hour - 2).clamp(0, 23), minute: 0);
  }

  @override
  void dispose() {
    _actividad.dispose();
    super.dispose();
  }

  DateTime get _inicio => DateTime(
        _fecha.year,
        _fecha.month,
        _fecha.day,
        _horaInicio.hour,
        _horaInicio.minute,
      );

  DateTime get _fin => _inicio.add(_cantidad);

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(ahora.year - 1),
      lastDate: DateTime(ahora.year + 1, 12, 31),
      helpText: 'Fecha de actividad',
    );
    if (fecha == null || !mounted) return;
    setState(() => _fecha = fecha);
  }

  Future<void> _elegirHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _horaInicio,
      helpText: 'Hora de inicio',
    );
    if (hora == null || !mounted) return;
    setState(() => _horaInicio = hora);
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      await ref.read(solicitudRepositoryProvider).crear(
            centroCostoId: _centroId!,
            inicio: _inicio,
            fin: _fin,
            justificacion: _actividad.text,
            jornadaId: widget.precargada?.jornadaId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Solicitud enviada. Verás el resultado aquí cuando la revisen.',
            ),
          ),
        );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final perfil = ref.watch(perfilProvider);
    final centrosAsync = ref.watch(centrosProvider);
    final centros = centrosAsync.valueOrNull ?? const <CentroCosto>[];
    final autorizador = ref.watch(miAutorizadorProvider);
    // Solo lugares activos: en uno desactivado ya no se registra trabajo.
    final lugares = parquesParaEntrada(
      ref.watch(parquesProvider).valueOrNull ?? const <Parque>[],
    )..sort((a, b) => a.nombre.compareTo(b.nombre));
    final extras = ref.watch(centrosPorLugarProvider).valueOrNull ?? const {};

    // Sin lugar elegido: el del horario de ese día, si lo tiene.
    if (_lugarId == null) {
      final yo = perfil.valueOrNull?.id;
      final horarios =
          yo == null ? null : ref.watch(horariosDeProvider(yo)).valueOrNull;
      for (final h in horarios ?? const <Horario>[]) {
        if (h.diaSemana == _fecha.weekday && h.parqueId != null) {
          _lugarId = h.parqueId;
        }
      }
    }
    Parque? lugar;
    for (final l in lugares) {
      if (l.id == _lugarId) lugar = l;
    }
    final centrosLugar = lugar == null
        ? const <CentroCosto>[]
        : centrosDeLugar(
            centroDelLugar: lugar.centroCostoId,
            extras: extras[lugar.id] ?? const {},
            centros: centros,
          );
    if (lugar != null && !centrosLugar.any((c) => c.id == _centroId)) {
      _centroId = lugar.centroCostoId;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Horas extras')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Registrar horas extras',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Llena los datos para la autorización y el registro de tus '
                'horas extras.',
                style: TextStyle(color: colores.onSurfaceVariant),
              ),
              if (widget.precargada != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colores.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.gps_fixed_rounded,
                        color: colores.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Detectado por tu marcaje GPS. Solo describe la '
                          'actividad realizada.',
                          style: TextStyle(color: colores.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _TarjetaSeleccion(
                      etiqueta: 'Fecha de actividad',
                      valor: formatearFecha(_fecha),
                      onTap: _elegirFecha,
                      icono: Icons.event_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TarjetaSeleccion(
                      etiqueta: 'Hora de inicio',
                      valor: formatearHora(_inicio),
                      onTap: _elegirHora,
                      icono: Icons.play_circle_outline_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Duration>(
                initialValue: _cantidad,
                decoration: const InputDecoration(
                  labelText: 'Cantidad de horas extras',
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
                items: [
                  for (final opcion in opcionesDeHoras)
                    DropdownMenuItem(
                      value: opcion,
                      child: Text(formatearDuracion(opcion)),
                    ),
                ],
                onChanged: (valor) {
                  if (valor != null) setState(() => _cantidad = valor);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Text(
                  'De ${formatearHora(_inicio)} a ${formatearHora(_fin)}'
                  '${_fin.day != _inicio.day ? ' del día siguiente' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colores.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _actividad,
                minLines: 3,
                maxLines: 8,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Actividad realizada',
                  alignLabelWithHint: true,
                  hintText: 'Ej. Cambio de bandas en la rueda de Andaria.',
                ),
                validator: (valor) {
                  final texto = valor?.trim() ?? '';
                  if (texto.length < 10) {
                    return 'Describe la actividad (mínimo 10 caracteres).';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              if (centrosAsync.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                )
              else if (centrosAsync.hasError)
                _MensajeEnLinea(
                  mensaje: 'No se pudieron cargar los centros de costo.',
                  onReintentar: () => ref.invalidate(centrosProvider),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: lugar?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Lugar',
                    helperText: 'Parque, Oficina Central o Bodega',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  items: [
                    for (final l in lugares)
                      DropdownMenuItem(value: l.id, child: Text(l.nombre)),
                  ],
                  onChanged: (valor) => setState(() {
                    _lugarId = valor;
                    _centroId = null;
                  }),
                  validator: (valor) =>
                      valor == null ? 'Elige dónde hiciste la actividad.' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey('ceco-${lugar?.id}'),
                  initialValue: _centroId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Centro de costo',
                    prefixIcon: Icon(Icons.account_tree_outlined),
                  ),
                  items: [
                    for (final c in centrosLugar)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.etiqueta, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: lugar == null
                      ? null
                      : (valor) => setState(() => _centroId = valor),
                  validator: (valor) =>
                      valor == null ? 'Elige el centro de costo.' : null,
                ),
              ],
              const SizedBox(height: 18),
              _PersonaQueAutoriza(autorizador: autorizador),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Enviar solicitud'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonaQueAutoriza extends StatelessWidget {
  const _PersonaQueAutoriza({required this.autorizador});

  final AsyncValue<({String nombre, String? puesto})?> autorizador;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final persona = autorizador.valueOrNull;
    final texto = autorizador.isLoading
        ? 'Buscando a tu jefe...'
        : persona == null
            ? 'Sin jefe asignado. La revisará un administrador.'
            : persona.puesto == null
                ? persona.nombre
                : '${persona.nombre} · ${persona.puesto}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: colores.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Persona que autoriza',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colores.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  texto,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colores.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaSeleccion extends StatelessWidget {
  const _TarjetaSeleccion({
    required this.etiqueta,
    required this.valor,
    required this.onTap,
    required this.icono,
  });

  final String etiqueta;
  final String valor;
  final VoidCallback onTap;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colores.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colores.outlineVariant, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 18, color: colores.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    etiqueta,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colores.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colores.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MensajeEnLinea extends StatelessWidget {
  const _MensajeEnLinea({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colores.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(color: colores.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
