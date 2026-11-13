import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/features/catalogo/domain/utils/centros.dart';
import 'package:carrousel_app/core/widgets/estado_widgets.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';
import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/admin/presentation/providers/admin_providers.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/catalogo/presentation/providers/catalogo_providers.dart';

/// Invitación de usuarios para administradores.
///
/// El formulario solo envía datos a la Edge Function `invitar-usuario`. El
/// servidor valida el rol del solicitante, su empresa y su subárbol; la app no
/// puede elevar roles ni asignar claims por su cuenta.
class InvitarUsuarioPage extends ConsumerStatefulWidget {
  const InvitarUsuarioPage({super.key});

  @override
  ConsumerState<InvitarUsuarioPage> createState() =>
      _InvitarUsuarioPageState();
}

class _InvitarUsuarioPageState extends ConsumerState<InvitarUsuarioPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _nombre = TextEditingController();

  RolUsuario _rol = RolUsuario.empleado;
  String? _centroId;
  bool _enviando = false;

  @override
  void dispose() {
    _email.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_centroId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el centro de costo destino.')),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      final invitacion =
          await ref.read(invitacionControllerProvider.notifier).invitar(
                email: _email.text,
                nombreCompleto: _nombre.text,
                rol: _rol,
                centroCostoId: _centroId!,
              );
      if (invitacion == null || !mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogo) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_rounded),
          title: const Text('Invitación enviada'),
          content: Text(
            'Enviamos un correo a ${invitacion.email} para que active su cuenta '
            'como ${invitacion.rolEtiqueta.toLowerCase()} en el centro de costo '
            'seleccionado. Al aceptar la invitación podrá iniciar sesión en '
            'Carrousel.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogo).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final perfilAsync = ref.watch(perfilProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Invitar usuario')),
      body: perfilAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando tu perfil...'),
        error: (error, _) => MensajeError(
          mensaje: 'No se pudo cargar tu perfil.',
          onReintentar: () => ref.invalidate(perfilProvider),
        ),
        data: (perfil) {
          if (perfil == null || !perfil.esAdmin) {
            return const EstadoVacio(
              icono: Icons.admin_panel_settings_outlined,
              titulo: 'Solo administradores',
              mensaje:
                  'Esta sección permite invitar usuarios al equipo de tu centro de costo.',
            );
          }
          return _formulario(context, perfil, colores);
        },
      ),
    );
  }

  Widget _formulario(
    BuildContext context,
    Perfil perfil,
    ColorScheme colores,
  ) {
    final centrosAsync = ref.watch(centrosProvider);
    final centros = centrosAsync.valueOrNull ?? const <CentroCosto>[];
    final subarbol = subarbolDe(centros, perfil.centroCostoId);

    if (_centroId == null && subarbol.isNotEmpty) {
      _centroId = subarbol.any((centro) => centro.id == perfil.centroCostoId)
          ? perfil.centroCostoId
          : subarbol.first.id;
    }

    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Suma a alguien a tu equipo',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'La persona recibirá una invitación por correo. Tú eliges su rol '
              'y el centro de costo al que pertenece dentro de tu subárbol.',
              style: TextStyle(color: colores.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.badge_outlined),
                hintText: 'Nombre y apellidos',
              ),
              validator: (valor) {
                final texto = valor?.trim() ?? '';
                if (texto.length < 2) {
                  return 'Escribe el nombre completo.';
                }
                if (texto.length > 120) {
                  return 'El nombre no puede superar 120 caracteres.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.mail_outline_rounded),
                hintText: 'persona@correo.com',
              ),
              validator: (valor) {
                final texto = valor?.trim() ?? '';
                final valido =
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(texto);
                if (!valido) return 'Escribe un correo válido.';
                if (texto.length > 320) {
                  return 'El correo no puede superar 320 caracteres.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<RolUsuario>(
              initialValue: _rol,
              decoration: const InputDecoration(
                labelText: 'Rol',
                prefixIcon: Icon(Icons.manage_accounts_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: RolUsuario.empleado,
                  child: Text('Empleado'),
                ),
                DropdownMenuItem(
                  value: RolUsuario.admin,
                  child: Text('Administrador'),
                ),
              ],
              onChanged: _enviando
                  ? null
                  : (valor) {
                      if (valor != null) setState(() => _rol = valor);
                    },
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _rol == RolUsuario.admin
                    ? 'Podrá revisar horas extras e invitar usuarios dentro de tu subárbol.'
                    : 'Podrá marcar jornadas y enviar solicitudes de horas extras.',
                style: TextStyle(
                  fontSize: 12,
                  color: colores.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
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
            else if (subarbol.isEmpty)
              _MensajeEnLinea(
                mensaje:
                    'No hay centros disponibles dentro de tu subárbol.',
                onReintentar: () => ref.invalidate(centrosProvider),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _centroId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Centro de costo',
                  prefixIcon: Icon(Icons.attractions_outlined),
                ),
                items: [
                  for (final centro in subarbol)
                    DropdownMenuItem(
                      value: centro.id,
                      child: Text(centro.nombre),
                    ),
                ],
                onChanged: _enviando
                    ? null
                    : (valor) => setState(() => _centroId = valor),
                validator: (valor) =>
                    valor == null ? 'Selecciona el centro de costo.' : null,
              ),
            const SizedBox(height: 18),
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
                    Icons.security_rounded,
                    color: colores.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Solo puedes invitar a centros de tu propio subárbol. '
                      'El rol y el alcance los valida el servidor; nadie puede '
                      'ascenderse a administrador desde la app.',
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
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(
                _enviando ? 'Enviando invitación...' : 'Enviar invitación',
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
