import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/utils/centros.dart';
import '../../core/utils/duraciones.dart';
import '../../core/widgets/ecosistema.dart';
import '../../core/widgets/estado_widgets.dart';
import '../../core/widgets/selector_ceco.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/centro_costo.dart';
import '../../providers/app_providers.dart';

/// Cuentas creadas por la propia persona que esperan asignación.
class RegistrosPage extends ConsumerWidget {
  const RegistrosPage({super.key});

  Future<void> _aprobar(
    BuildContext context,
    WidgetRef ref,
    Registro registro,
  ) async {
    final aprobado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaAprobar(registro: registro),
    );
    if (aprobado == true && context.mounted) {
      ref.invalidate(registrosProvider);
      ref.invalidate(resumenAdminProvider);
      mostrarAviso(context, '${registro.nombre} ya puede marcar su jornada.',
          tipo: TipoAviso.success);
    }
  }

  Future<void> _rechazar(
    BuildContext context,
    WidgetRef ref,
    Registro registro,
  ) async {
    final motivo = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('¿Rechazar a ${registro.nombre}?'),
        content: TextField(
          controller: motivo,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Motivo (lo verá la persona)'),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogo).colorScheme.error,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    final texto = motivo.text;
    motivo.dispose();
    if (confirmado != true || !context.mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .rechazarRegistro(registroId: registro.id, motivo: texto);
      ref.invalidate(registrosProvider);
      ref.invalidate(resumenAdminProvider);
      if (context.mounted) mostrarAviso(context, 'Registro rechazado.');
    } catch (error) {
      if (context.mounted) {
        mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registrosAsync = ref.watch(registrosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Registros'), bottom: const FranjaMarca()),
      body: registrosAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando registros...'),
        error: (_, _) => MensajeError(
          mensaje: 'No se pudieron cargar los registros.',
          onReintentar: () => ref.invalidate(registrosProvider),
        ),
        data: (registros) {
          final pendientes = registros.where((r) => r.pendiente).toList();
          final revisados = registros.where((r) => !r.pendiente).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(registrosProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const EncabezadoPagina(
                  eyebrow: 'Registro de colaboradores',
                  titulo: 'Cuentas por asignar',
                  subtitulo:
                      'Asigna centro de costo y puesto para que la persona pueda marcar.',
                ),
                if (pendientes.isEmpty)
                  const AvisoEnPagina(
                    tipo: TipoAviso.success,
                    mensaje: 'No hay registros pendientes.',
                  ),
                for (final r in pendientes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.nombre,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          Text('${r.email}'
                              '${r.telefono == null ? '' : ' · ${r.telefono}'}'),
                          Text('Solicitó ${formatearFechaHora(r.creadoEn)}',
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _rechazar(context, ref, r),
                                  child: const Text('Rechazar'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _aprobar(context, ref, r),
                                  child: const Text('Asignar'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (revisados.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Historial',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  for (final r in revisados)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.nombre),
                      subtitle: Text(r.rechazado
                          ? 'Rechazado: ${r.motivo ?? ''}'
                          : 'Aprobado'),
                      trailing: Icon(r.rechazado
                          ? Icons.block_rounded
                          : Icons.check_circle_rounded),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HojaAprobar extends ConsumerStatefulWidget {
  const _HojaAprobar({required this.registro});

  final Registro registro;

  @override
  ConsumerState<_HojaAprobar> createState() => _HojaAprobarState();
}

class _HojaAprobarState extends ConsumerState<_HojaAprobar> {
  final _formKey = GlobalKey<FormState>();
  String? _centroId;
  String? _puestoId;
  bool _guardando = false;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await ref.read(adminRepositoryProvider).aprobarRegistro(
            registroId: widget.registro.id,
            centroId: _centroId!,
            puestoId: _puestoId,
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
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final centros = ref.watch(centrosProvider).valueOrNull ?? const <CentroCosto>[];
    final subarbol =
        perfil == null ? centros : subarbolDe(centros, perfil.centroCostoId);
    final principales = centrosPrincipales(subarbol);
    // Un admin de un solo parque no tiene "principales" debajo: se le ofrece
    // su propio subárbol.
    final alcance = principales.isEmpty ? subarbol : principales;
    final puestos = ref.watch(puestosProvider).valueOrNull ?? const [];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EncabezadoPagina(
                eyebrow: 'Asignar cuenta',
                titulo: widget.registro.nombre,
                subtitulo: widget.registro.email,
              ),
              SelectorCeco(
                centros: alcance,
                etiqueta: 'Parque o área (centro de costo)',
                onChanged: (id) => setState(() => _centroId = id),
                validator: (v) =>
                    v == null ? 'Elige el centro de costo.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _puestoId,
                decoration: const InputDecoration(labelText: 'Puesto'),
                items: [
                  for (final p in puestos)
                    DropdownMenuItem(value: p.id, child: Text(p.nombre)),
                ],
                onChanged: (v) => setState(() => _puestoId = v),
              ),
              const SizedBox(height: 8),
              const AvisoEnPagina(
                mensaje:
                    'La cuenta queda como empleado. Para hacerla administrador usa "Invitar usuario".',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: const Text('Asignar y dar acceso'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
