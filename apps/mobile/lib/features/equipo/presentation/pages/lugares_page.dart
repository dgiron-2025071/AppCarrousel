import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/core/widgets/estado_widgets.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque_centro.dart';
import 'package:carrousel_app/features/catalogo/presentation/providers/catalogo_providers.dart';
import 'package:carrousel_app/features/equipo/presentation/providers/equipo_providers.dart';

/// Centros de costo habilitados por lugar.
///
/// El CECO principal se deriva de `parques.centro_costo_id` y no se edita aquí;
/// esta pantalla agregar CECOs adicionales, activa o desactiva y deja el
/// principal siempre disponible.
class LugaresPage extends ConsumerStatefulWidget {
  const LugaresPage({super.key});

  @override
  ConsumerState<LugaresPage> createState() => _LugaresPageState();
}

class _LugaresPageState extends ConsumerState<LugaresPage> {
  String? _parqueId;

  Future<void> _agregar(Parque parque, List<CentroCosto> disponibles) async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    if (perfil == null) return;

    final centroId = await showDialog<String>(
      context: context,
      builder: (_) =>
          _DialogoAgregarCentro(parque: parque, centros: disponibles),
    );
    if (centroId == null || !mounted) return;

    try {
      await ref.read(agregarCentroLugarProvider)(
        empresaId: perfil.empresaId,
        parqueId: parque.id,
        centroCostoId: centroId,
      );
      ref.invalidate(parquesCentrosProvider);
      ref.invalidate(lugaresProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Centro de costo habilitado.')),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }

  Future<void> _cambiarActivo(ParqueCentro enlace, bool activo) async {
    try {
      await ref.read(cambiarCentroLugarProvider)(
        enlaceId: enlace.id,
        activo: activo,
      );
      ref.invalidate(parquesCentrosProvider);
      ref.invalidate(lugaresProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final parquesAsync = ref.watch(parquesProvider);
    final enlacesAsync = ref.watch(parquesCentrosProvider);
    final centrosAsync = ref.watch(centrosProvider);

    if (parquesAsync.isLoading ||
        enlacesAsync.isLoading ||
        centrosAsync.isLoading) {
      return const CargandoWidget(mensaje: 'Cargando lugares...');
    }

    if (parquesAsync.hasError ||
        enlacesAsync.hasError ||
        centrosAsync.hasError) {
      return MensajeError(
        mensaje: 'No se pudieron cargar los lugares y centros de costo.',
        onReintentar: () {
          ref.invalidate(parquesProvider);
          ref.invalidate(parquesCentrosProvider);
          ref.invalidate(centrosProvider);
        },
      );
    }

    final parques = parquesAsync.valueOrNull ?? const <Parque>[];
    final enlaces = enlacesAsync.valueOrNull ?? const <ParqueCentro>[];
    final centros = centrosAsync.valueOrNull ?? const <CentroCosto>[];

    if (parques.isEmpty) {
      return const EstadoVacio(
        icono: Icons.place_outlined,
        titulo: 'Sin lugares',
        mensaje: 'Tu empresa aún no tiene parques o lugares configurados. Crea uno desde el panel de Supabase.',
      );
    }

    final parqueSeleccionado = parques.firstWhere(
      (parque) => parque.id == _parqueId,
      orElse: () => parques.first,
    );
    final centrosPorId = {for (final centro in centros) centro.id: centro};
    final enlacesDelParque = enlaces
        .where((enlace) => enlace.parqueId == parqueSeleccionado.id)
        .toList(growable: false);
    final idsHabilitados = {
      for (final enlace in enlacesDelParque) enlace.centroCostoId,
    };
    final disponibles = centros
        .where((centro) => !idsHabilitados.contains(centro.id))
        .toList(growable: false);
    enlacesDelParque.sort((a, b) {
      if (a.principal != b.principal) return a.principal ? -1 : 1;
      final nombreA = centrosPorId[a.centroCostoId]?.nombre ?? '';
      final nombreB = centrosPorId[b.centroCostoId]?.nombre ?? '';
      return nombreA.toLowerCase().compareTo(nombreB.toLowerCase());
    });

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text(
          'Centros por lugar',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Habilita los centros de costo que se pueden elegir al registrar '
          'horas extras en cada lugar.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: parqueSeleccionado.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Lugar',
            prefixIcon: Icon(Icons.place_outlined),
          ),
          items: [
            for (final parque in parques)
              DropdownMenuItem(
                value: parque.id,
                child: Text(
                  parque.codigo.isEmpty
                      ? parque.nombre
                      : '${parque.nombre} (${parque.codigo})',
                ),
              ),
          ],
          onChanged: (valor) => setState(() => _parqueId = valor),
        ),
        const SizedBox(height: 16),
        if (enlacesDelParque.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 8),
            child: Text('Este lugar no tiene centros habilitados todavía.'),
          )
        else
          for (final enlace in enlacesDelParque)
            _FilaCentro(
              enlace: enlace,
              centro: centrosPorId[enlace.centroCostoId],
              onCambiarActivo: (activo) => _cambiarActivo(enlace, activo),
            ),
        const SizedBox(height: 10),
        if (disponibles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Todos los centros de la empresa ya están habilitados en este lugar.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: () => _agregar(parqueSeleccionado, disponibles),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Habilitar otro centro de costo'),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'El centro principal se cambia moviendo el centro del parque. '
                  'Las solicitudes históricas conservan el centro con el que se '
                  'registraron.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilaCentro extends StatelessWidget {
  const _FilaCentro({
    required this.enlace,
    required this.centro,
    required this.onCambiarActivo,
  });

  final ParqueCentro enlace;
  final CentroCosto? centro;
  final ValueChanged<bool> onCambiarActivo;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: colores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.outlineVariant, width: 0.7),
      ),
      child: Row(
        children: [
          Icon(
            enlace.principal ? Icons.star_rounded : Icons.account_tree_outlined,
            color: enlace.principal
                ? colores.primary
                : colores.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        centro?.nombre ?? 'Centro de costo',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (enlace.principal) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colores.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Principal',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colores.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (centro != null && centro!.codigo.isNotEmpty)
                  Text(
                    centro!.codigo,
                    style: TextStyle(
                      fontSize: 12,
                      color: colores.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (enlace.principal)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Siempre activo',
                style: TextStyle(fontSize: 11, color: colores.onSurfaceVariant),
              ),
            )
          else
            Switch(value: enlace.activo, onChanged: onCambiarActivo),
        ],
      ),
    );
  }
}

class _DialogoAgregarCentro extends StatefulWidget {
  const _DialogoAgregarCentro({required this.parque, required this.centros});

  final Parque parque;
  final List<CentroCosto> centros;

  @override
  State<_DialogoAgregarCentro> createState() => _DialogoAgregarCentroState();
}

class _DialogoAgregarCentroState extends State<_DialogoAgregarCentro> {
  String? _centroId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Habilitar centro de costo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.parque.nombre,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _centroId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Centro de costo',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              items: [
                for (final centro in widget.centros)
                  DropdownMenuItem(
                    value: centro.id,
                    child: Text(
                      centro.codigo.isEmpty
                          ? centro.nombre
                          : '${centro.nombre} (${centro.codigo})',
                    ),
                  ),
              ],
              onChanged: (valor) => setState(() => _centroId = valor),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _centroId == null
              ? null
              : () => Navigator.of(context).pop(_centroId),
          child: const Text('Habilitar'),
        ),
      ],
    );
  }
}
