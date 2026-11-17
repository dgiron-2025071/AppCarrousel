import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/core/utils/zonas_horarias.dart';
import 'package:carrousel_app/core/widgets/estado_widgets.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/configuracion/domain/entities/configuracion_empresa.dart';
import 'package:carrousel_app/features/configuracion/presentation/providers/configuracion_providers.dart';

/// Ajustes de la empresa que afectan el marcaje y los reportes.
class ConfiguracionEmpresaPage extends ConsumerWidget {
  const ConfiguracionEmpresaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).valueOrNull;
    if (perfil == null) {
      return const CargandoWidget(mensaje: 'Cargando configuración...');
    }

    final configAsync = ref.watch(
      configuracionEmpresaProvider(perfil.empresaId),
    );
    return configAsync.when(
      loading: () => const CargandoWidget(mensaje: 'Cargando configuración...'),
      error: (error, _) => MensajeError(
        mensaje: 'No se pudo cargar la configuración de la empresa.',
        onReintentar: () =>
            ref.invalidate(configuracionEmpresaProvider(perfil.empresaId)),
      ),
      data: (config) => _Formulario(config: config),
    );
  }
}

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({required this.config});

  final ConfiguracionEmpresa config;

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _zona;
  late final TextEditingController _gps;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _zona = TextEditingController(text: widget.config.zonaHoraria);
    _gps = TextEditingController(
      text: widget.config.gpsPrecisionMaximaMetros.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _Formulario oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El provider puede recargarse (guardado, Realtime o reintento) y los
    // controladores deben seguir el valor vigente, no solo el inicial.
    if (oldWidget.config.zonaHoraria != widget.config.zonaHoraria &&
        _zona.text != widget.config.zonaHoraria) {
      _zona.text = widget.config.zonaHoraria;
    }
    final gps = widget.config.gpsPrecisionMaximaMetros.toString();
    if (oldWidget.config.gpsPrecisionMaximaMetros !=
            widget.config.gpsPrecisionMaximaMetros &&
        _gps.text != gps) {
      _gps.text = gps;
    }
  }

  @override
  void dispose() {
    _zona.dispose();
    _gps.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    try {
      await ref.read(guardarConfiguracionProvider)(
        empresaId: widget.config.id,
        zonaHoraria: _zona.text,
        gpsPrecisionMaximaMetros: int.parse(_gps.text.trim()),
      );
      ref.invalidate(configuracionEmpresaProvider(widget.config.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Configuración guardada. Aplica a los próximos marcajes.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text(
          'Configuración de la empresa',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          widget.config.nombre,
          style: TextStyle(color: colores.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _zona,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Zona horaria (IANA)',
                  prefixIcon: Icon(Icons.public_rounded),
                  helperText: 'Ejemplo: America/Guatemala',
                ),
                validator: (valor) {
                  final texto = valor?.trim() ?? '';
                  if (texto.isEmpty) return 'Escribe la zona horaria.';
                  if (texto.length > 64) return 'Usa máximo 64 caracteres.';
                  if (!zonaHorariaValida(texto)) {
                    return 'Usa una zona IANA válida, por ejemplo America/Guatemala.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gps,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onFieldSubmitted: (_) => _guardar(),
                decoration: const InputDecoration(
                  labelText: 'Precisión GPS máxima (metros)',
                  prefixIcon: Icon(Icons.gps_fixed_rounded),
                  helperText:
                      'Entre 10 y 1000 metros. Por encima se marca '
                      'como GPS impreciso.',
                ),
                validator: (valor) {
                  final numero = int.tryParse(valor?.trim() ?? '');
                  if (numero == null) return 'Escribe un número entero.';
                  if (numero < 10 || numero > 1000) {
                    return 'Usa un valor entre 10 y 1000 metros.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(
                'La zona horaria define las fechas y horas locales de las '
                'jornadas, los horarios y los reportes. El umbral de GPS se '
                'usa para detectar marcajes imprecisos.',
                style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar configuración'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
