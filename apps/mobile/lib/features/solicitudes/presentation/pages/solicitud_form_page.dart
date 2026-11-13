import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/core/utils/duraciones.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/catalogo/presentation/providers/catalogo_providers.dart';
import 'package:carrousel_app/features/solicitudes/presentation/providers/solicitud_providers.dart';

/// Formulario de horas extras.
///
/// El especialista indica el rango, el centro/parque donde apoyó y la
/// justificación. La solicitud nace en estado `pendiente`; el admin de su
/// centro la revisa y el resultado le llega por Realtime.
class SolicitudFormPage extends ConsumerStatefulWidget {
  const SolicitudFormPage({super.key});

  @override
  ConsumerState<SolicitudFormPage> createState() => _SolicitudFormPageState();
}

class _SolicitudFormPageState extends ConsumerState<SolicitudFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _justificacion = TextEditingController();

  late DateTime _inicio;
  late DateTime _fin;
  String? _centroId;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _inicio = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      ahora.hour,
    ).subtract(const Duration(hours: 2));
    _fin = _inicio.add(const Duration(hours: 2));
  }

  @override
  void dispose() {
    _justificacion.dispose();
    super.dispose();
  }

  Duration get _duracion => _fin.difference(_inicio);

  Future<DateTime?> _elegirFechaHora(DateTime actual) async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(ahora.year - 1),
      lastDate: DateTime(ahora.year + 1, 12, 31),
      helpText: 'Fecha de las horas extras',
    );
    if (fecha == null || !mounted) return null;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(actual),
      helpText: 'Hora',
    );
    if (hora == null) return null;

    return DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      hora.hour,
      hora.minute,
    );
  }

  Future<void> _cambiarInicio() async {
    final valor = await _elegirFechaHora(_inicio);
    if (valor == null || !mounted) return;
    setState(() {
      _inicio = valor;
      if (!_fin.isAfter(_inicio)) {
        _fin = _inicio.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _cambiarFin() async {
    final valor = await _elegirFechaHora(_fin);
    if (valor == null || !mounted) return;
    if (!valor.isAfter(_inicio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La hora final debe ser posterior a la inicial.'),
        ),
      );
      return;
    }
    setState(() => _fin = valor);
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_centroId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona el parque o centro donde apoyaste.'),
        ),
      );
      return;
    }
    if (!_fin.isAfter(_inicio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La hora final debe ser posterior a la inicial.'),
        ),
      );
      return;
    }
    if (_duracion > const Duration(hours: 24)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Una solicitud no puede superar las 24 horas.'),
        ),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      await ref.read(crearSolicitudProvider)(
        centroCostoId: _centroId!,
        inicio: _inicio,
        fin: _fin,
        justificacion: _justificacion.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Solicitud enviada. Tu administrador la revisará y verás el resultado aquí.',
            ),
          ),
        );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeDeError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final perfil = ref.watch(perfilProvider);
    final centrosAsync = ref.watch(centrosProvider);
    final centros = centrosAsync.valueOrNull ?? const <CentroCosto>[];

    _centroId ??= perfil.valueOrNull?.centroCostoId;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva solicitud')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Registra el apoyo en otro parque',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Indica el rango de horas, el centro donde apoyaste y el motivo. '
                'Tu administrador recibirá la solicitud en tiempo real.',
                style: TextStyle(color: colores.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _TarjetaSeleccion(
                      etiqueta: 'Desde',
                      fecha: _inicio,
                      onTap: _cambiarInicio,
                      icono: Icons.play_circle_outline_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TarjetaSeleccion(
                      etiqueta: 'Hasta',
                      fecha: _fin,
                      onTap: _cambiarFin,
                      icono: Icons.stop_circle_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _duracion > const Duration(hours: 24)
                      ? colores.errorContainer
                      : colores.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 18, color: colores.primary),
                    const SizedBox(width: 8),
                    Text(
                      _duracion.isNegative
                          ? 'El rango de horas es inválido.'
                          : 'Total: ${formatearDuracion(_duracion)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
              else
                DropdownButtonFormField<String>(
                  initialValue: _centroId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Parque / centro de costo donde apoyaste',
                    prefixIcon: Icon(Icons.attractions_outlined),
                  ),
                  items: [
                    for (final centro in centros)
                      DropdownMenuItem(
                        value: centro.id,
                        child: Text(centro.nombre),
                      ),
                  ],
                  onChanged: (valor) => setState(() => _centroId = valor),
                  validator: (valor) => valor == null
                      ? 'Selecciona el centro donde apoyaste.'
                      : null,
                ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _justificacion,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Justificación',
                  alignLabelWithHint: true,
                  hintText:
                      'Explica por qué realizaste estas horas extras y qué apoyo brindaste.',
                ),
                validator: (valor) {
                  final texto = valor?.trim() ?? '';
                  if (texto.length < 10) {
                    return 'Escribe al menos 10 caracteres.';
                  }
                  if (texto.length > 2000) {
                    return 'La justificación no puede superar 2000 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colores.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: colores.onSecondaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'La solicitud quedará pendiente hasta que el administrador '
                        'de tu centro la apruebe o rechace. El resultado aparecerá '
                        'automáticamente en tu historial.',
                        style: TextStyle(
                          color: colores.onSecondaryContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

class _TarjetaSeleccion extends StatelessWidget {
  const _TarjetaSeleccion({
    required this.etiqueta,
    required this.fecha,
    required this.onTap,
    required this.icono,
  });

  final String etiqueta;
  final DateTime fecha;
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
                Text(
                  etiqueta,
                  style: TextStyle(
                    fontSize: 12,
                    color: colores.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatearFecha(fecha),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              formatearHora(fecha),
              style: TextStyle(
                fontSize: 18,
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
          TextButton(
            onPressed: onReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
