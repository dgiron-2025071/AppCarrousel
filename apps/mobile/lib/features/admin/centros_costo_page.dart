import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/centros.dart';
import '../../core/widgets/ecosistema.dart';
import '../../core/widgets/estado_widgets.dart';
import '../../data/models/centro_costo.dart';
import '../../providers/app_providers.dart';

/// Catálogo de centros de costo: parques y áreas principales con sus
/// sub-centros. El admin crea, renombra o elimina dentro de su alcance.
class CentrosCostoPage extends ConsumerStatefulWidget {
  const CentrosCostoPage({super.key});

  @override
  ConsumerState<CentrosCostoPage> createState() => _CentrosCostoPageState();
}

class _CentrosCostoPageState extends ConsumerState<CentrosCostoPage> {
  String _consulta = '';

  Future<void> _editar({CentroCosto? centro, CentroCosto? padre}) async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    if (perfil == null) return;
    final codigo = TextEditingController(text: centro?.codigo ?? (padre == null ? '' : '${padre.codigo}.'));
    final nombre = TextEditingController(text: centro?.nombre);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(centro == null
            ? (padre == null ? 'Nuevo parque o área' : 'Nuevo sub-centro de ${padre.nombre}')
            : 'Editar ${centro.etiqueta}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: codigo, decoration: const InputDecoration(labelText: 'Código')),
            const SizedBox(height: 12),
            TextField(
              controller: nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogo).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final cod = codigo.text, nom = nombre.text;
    codigo.dispose();
    nombre.dispose();
    if (ok != true || !mounted) return;
    if (cod.trim().isEmpty || nom.trim().length < 2) {
      mostrarAviso(context, 'Escribe código y nombre.', tipo: TipoAviso.warning);
      return;
    }
    final centros = ref.read(centrosProvider).valueOrNull ?? const <CentroCosto>[];
    String? raiz;
    for (final c in centros) {
      if (c.padreId == null) raiz = c.id;
    }
    try {
      await ref.read(adminRepositoryProvider).guardarCentro(
            id: centro?.id,
            empresaId: perfil.empresaId,
            padreId: padre?.id ?? raiz,
            codigo: cod,
            nombre: nom,
          );
      ref.invalidate(centrosProvider);
      if (mounted) mostrarAviso(context, 'Centro de costo guardado.', tipo: TipoAviso.success);
    } catch (error) {
      if (mounted) mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
    }
  }

  Future<void> _eliminar(CentroCosto centro) async {
    if (!await confirmar(
      context,
      pregunta: '¿Eliminar ${centro.etiqueta}?',
      detalle: 'Solo se puede si no tiene sub-centros, lugares, personas ni solicitudes.',
      aceptar: 'Eliminar',
    )) {
      return;
    }
    try {
      await ref.read(adminRepositoryProvider).eliminarCentro(centro.id);
      ref.invalidate(centrosProvider);
      if (mounted) mostrarAviso(context, 'Centro eliminado.', tipo: TipoAviso.success);
    } catch (error) {
      if (mounted) mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
    }
  }

  Widget _menu(CentroCosto centro, {required bool principal}) => PopupMenuButton<String>(
        onSelected: (accion) => switch (accion) {
          'sub' => _editar(padre: centro),
          'editar' => _editar(centro: centro),
          _ => _eliminar(centro),
        },
        itemBuilder: (_) => [
          if (principal) const PopupMenuItem(value: 'sub', child: Text('Agregar sub-centro')),
          const PopupMenuItem(value: 'editar', child: Text('Editar')),
          const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final centrosAsync = ref.watch(centrosProvider);
    final c = ColoresCarrousel.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Centros de costo'), bottom: const FranjaMarca()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo'),
      ),
      body: centrosAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando centros de costo...'),
        error: (_, _) => MensajeError(
          mensaje: 'No se pudieron cargar los centros de costo.',
          onReintentar: () => ref.invalidate(centrosProvider),
        ),
        data: (centros) {
          final hijos = <String, List<CentroCosto>>{};
          for (final x in centros) {
            if (x.padreId != null) hijos.putIfAbsent(x.padreId!, () => []).add(x);
          }
          final principales = filtrarCentros(centrosPrincipales(centros), _consulta);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              EncabezadoPagina(
                eyebrow: 'Administración',
                titulo: 'Centros de costo',
                subtitulo: '${centrosPrincipales(centros).length} parques y áreas · '
                    '${centros.length - 1} en total con sub-centros.',
              ),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar por código o nombre',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _consulta = v),
              ),
              const SizedBox(height: 12),
              for (final p in principales)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    shape: const Border(),
                    title: Text(p.etiqueta, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${hijos[p.id]?.length ?? 0} sub-centros',
                        style: TextStyle(color: c.muted, fontSize: 12)),
                    trailing: _menu(p, principal: true),
                    children: [
                      for (final h in (hijos[p.id] ?? const <CentroCosto>[])
                        ..sort((a, b) => a.codigo.compareTo(b.codigo)))
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 32, right: 4),
                          title: Text(h.etiqueta),
                          trailing: _menu(h, principal: false),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
