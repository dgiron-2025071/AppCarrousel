import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/core/widgets/estado_widgets.dart';
import 'package:carrousel_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/registro/domain/entities/mi_registro.dart';
import 'package:carrousel_app/features/registro/presentation/providers/registro_providers.dart';

/// Alta de una cuenta autenticada que aún no tiene perfil de negocio.
///
/// El usuario envía el código de empresa y su nombre; la solicitud queda en
/// `registros_pendientes` hasta que un administrador la apruebe y fije el rol
/// `empleado`.
class SolicitudAltaPage extends ConsumerStatefulWidget {
  const SolicitudAltaPage({
    super.key,
    required this.email,
    required this.nombreInicial,
  });

  final String email;
  final String nombreInicial;

  @override
  ConsumerState<SolicitudAltaPage> createState() => _SolicitudAltaPageState();
}

class _SolicitudAltaPageState extends ConsumerState<SolicitudAltaPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  final _codigo = TextEditingController();
  final _puesto = TextEditingController();
  String _tipoPuesto = 'especialista';
  bool _enviando = false;
  bool _actualizando = false;
  bool _mostrarFormulario = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.nombreInicial);
  }

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
    _puesto.dispose();
    super.dispose();
  }

  String get _puestoDeclarado =>
      _tipoPuesto == 'especialista' ? 'Especialista' : _puesto.text.trim();

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await ref.read(solicitarRegistroProvider)(
        codigoEmpresa: _codigo.text,
        nombreCompleto: _nombre.text,
        puesto: _puestoDeclarado,
      );
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mostrarFormulario = false;
      });
      ref.invalidate(miRegistroProvider);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Solicitud enviada. Un administrador revisará tu alta.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = mensajeDeError(error);
      });
    }
  }

  Future<void> _refrescar() async {
    ref.invalidate(miRegistroProvider);
    try {
      await ref.read(miRegistroProvider.future);
    } catch (_) {
      // El estado de error del provider se muestra en la pantalla.
    }
  }

  Future<void> _actualizarAcceso() async {
    setState(() => _actualizando = true);
    try {
      final ok = await ref
          .read(authControllerProvider.notifier)
          .refrescarSesion();
      if (!mounted) return;
      if (!ok) {
        final error = ref.read(authControllerProvider).error;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                error?.toString() ?? 'No se pudo actualizar el acceso.',
              ),
            ),
          );
        return;
      }

      ref.invalidate(perfilProvider);
      ref.invalidate(miRegistroProvider);
    } finally {
      // Sin este reset un fallo dejaba el botón deshabilitado para siempre.
      if (mounted) setState(() => _actualizando = false);
    }
  }

  void _cerrarSesion() {
    ref.read(authControllerProvider.notifier).cerrarSesion();
  }

  @override
  Widget build(BuildContext context) {
    final registroAsync = ref.watch(miRegistroProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: registroAsync.when(
                loading: () =>
                    const CargandoWidget(mensaje: 'Revisando tu registro...'),
                error: (error, _) => _ErrorAlta(
                  mensaje: mensajeDeError(error),
                  onReintentar: _refrescar,
                  onCerrarSesion: _cerrarSesion,
                ),
                data: (registro) => _contenido(context, registro),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenido(BuildContext context, MiRegistro? registro) {
    final colores = Theme.of(context).colorScheme;

    final Widget cuerpo;
    if (registro == null) {
      cuerpo = _formulario(context);
    } else if (registro.aprobado) {
      cuerpo = _aprobado(context);
    } else if (registro.pendiente) {
      cuerpo = _pendiente(context, registro);
    } else if (_mostrarFormulario) {
      cuerpo = _formulario(context, motivoAnterior: registro.motivoRechazo);
    } else {
      cuerpo = _rechazado(context, registro);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.attractions_rounded, size: 56, color: colores.primary),
        const SizedBox(height: 16),
        Text(
          'Completa tu registro',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'La cuenta ${widget.email} todavía no tiene empresa, centro de costo ni rol asignados.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colores.onSurfaceVariant),
        ),
        const SizedBox(height: 26),
        cuerpo,
        const SizedBox(height: 18),
        TextButton(
          onPressed: _cerrarSesion,
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }

  Widget _formulario(BuildContext context, {String? motivoAnterior}) {
    final colores = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (motivoAnterior != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colores.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Motivo del rechazo anterior: $motivoAnterior',
                style: TextStyle(color: colores.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (valor) {
              final texto = valor?.trim() ?? '';
              if (texto.isEmpty) return 'Escribe tu nombre completo.';
              if (texto.length > 160) return 'Usa máximo 160 caracteres.';
              return null;
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Puesto',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          RadioGroup<String>(
            groupValue: _tipoPuesto,
            onChanged: (valor) =>
                setState(() => _tipoPuesto = valor ?? 'especialista'),
            child: Column(
              children: const [
                RadioListTile<String>(
                  title: Text('Especialista'),
                  value: 'especialista',
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  title: Text('Otro'),
                  subtitle: Text('Escribe el puesto que tienes.'),
                  value: 'otro',
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (_tipoPuesto == 'otro') ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _puesto,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 120,
              autofillHints: const [AutofillHints.jobTitle],
              decoration: const InputDecoration(
                labelText: 'Tu puesto',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (valor) {
                final texto = valor?.trim() ?? '';
                if (texto.isEmpty) return 'Escribe tu puesto.';
                if (texto.length > 120) return 'Usa máximo 120 caracteres.';
                return null;
              },
            ),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _codigo,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _enviar(),
            decoration: const InputDecoration(
              labelText: 'Código de empresa',
              prefixIcon: Icon(Icons.domain_rounded),
              helperText: 'Te lo entrega el administrador de tu empresa.',
            ),
            validator: (valor) {
              if (valor == null || valor.trim().isEmpty) {
                return 'Escribe el código de empresa.';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _BannerError(mensaje: _error!),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _enviando ? null : _enviar,
            child: _enviando
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text('Enviar solicitud'),
          ),
          const SizedBox(height: 12),
          Text(
            'Un administrador revisará tu alta. Hasta entonces no podrás marcar '
            'jornadas ni crear solicitudes de horas extras.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _pendiente(BuildContext context, MiRegistro registro) {
    final colores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EstadoPanel(
          icono: Icons.hourglass_top_rounded,
          color: colores.secondaryContainer,
          colorIcono: colores.onSecondaryContainer,
          titulo: 'Solicitud en revisión',
          mensaje:
              'Tu solicitud fue enviada el ${_fecha(registro.creadoEn)}. '
              'Puesto declarado: ${registro.puesto ?? 'Especialista'}.\n\n'
              'Cuando un administrador la apruebe podrás entrar a la app.',
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _refrescar,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Actualizar estado'),
        ),
      ],
    );
  }

  Widget _rechazado(BuildContext context, MiRegistro registro) {
    final colores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EstadoPanel(
          icono: Icons.cancel_outlined,
          color: colores.errorContainer,
          colorIcono: colores.onErrorContainer,
          titulo: 'Solicitud rechazada',
          mensaje:
              registro.motivoRechazo ??
              'Un administrador rechazó tu solicitud. Corrige los datos y '
                  'vuelve a intentarlo.',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => setState(() => _mostrarFormulario = true),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Enviar nueva solicitud'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _refrescar,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Actualizar estado'),
        ),
      ],
    );
  }

  Widget _aprobado(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EstadoPanel(
          icono: Icons.verified_user_rounded,
          color: colores.primaryContainer,
          colorIcono: colores.onPrimaryContainer,
          titulo: '¡Tu alta fue aprobada!',
          mensaje:
              'Actualiza tu acceso para cargar el perfil y entrar a Carrousel. '
              'Si acabas de ser aprobado, este paso renueva tus permisos.',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _actualizando ? null : _actualizarAcceso,
          icon: _actualizando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.login_rounded),
          label: const Text('Actualizar acceso'),
        ),
      ],
    );
  }

  static String _fecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }
}

class _EstadoPanel extends StatelessWidget {
  const _EstadoPanel({
    required this.icono,
    required this.color,
    required this.colorIcono,
    required this.titulo,
    required this.mensaje,
  });

  final IconData icono;
  final Color color;
  final Color colorIcono;
  final String titulo;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colores.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colores.outlineVariant, width: 0.7),
      ),
      child: Column(
        children: [
          Container(
            height: 54,
            width: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icono, color: colorIcono, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: TextStyle(color: colores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BannerError extends StatelessWidget {
  const _BannerError({required this.mensaje});

  final String mensaje;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: colores.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(color: colores.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorAlta extends StatelessWidget {
  const _ErrorAlta({
    required this.mensaje,
    required this.onReintentar,
    required this.onCerrarSesion,
  });

  final String mensaje;
  final VoidCallback onReintentar;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MensajeError(
          mensaje: 'No se pudo consultar tu registro.\n\n$mensaje',
          icono: Icons.cloud_off_rounded,
          onReintentar: onReintentar,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCerrarSesion,
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
