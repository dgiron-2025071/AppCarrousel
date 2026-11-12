import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/centros.dart';
import '../../core/widgets/ecosistema.dart';
import '../../core/widgets/estado_widgets.dart';
import '../../core/widgets/selector_ceco.dart';
import '../../data/models/centro_costo.dart';
import '../../data/models/parque.dart';
import '../../providers/app_providers.dart';

/// Lugares de trabajo (parques, Oficina Central, Bodega): el admin los crea,
/// edita su geocerca y centros de costo, o los elimina.
class LugaresPage extends ConsumerWidget {
  const LugaresPage({super.key});

  Future<void> _abrir(BuildContext context, WidgetRef ref, [Parque? lugar]) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LugarEditorPage(lugar: lugar)),
    );
    if (guardado == true) {
      ref.invalidate(parquesProvider);
      ref.invalidate(centrosPorLugarProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lugaresAsync = ref.watch(parquesProvider);
    final centros = {
      for (final c in ref.watch(centrosProvider).valueOrNull ?? const <CentroCosto>[]) c.id: c,
    };
    final extras = ref.watch(centrosPorLugarProvider).valueOrNull ?? const {};
    final c = ColoresCarrousel.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Lugares'), bottom: const FranjaMarca()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrir(context, ref),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Nuevo lugar'),
      ),
      body: lugaresAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando lugares...'),
        error: (_, _) => MensajeError(
          mensaje: 'No se pudieron cargar los lugares.',
          onReintentar: () => ref.invalidate(parquesProvider),
        ),
        data: (lugares) {
          final ordenados = [...lugares]..sort((a, b) => a.nombre.compareTo(b.nombre));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              EncabezadoPagina(
                eyebrow: 'Administración',
                titulo: 'Lugares de trabajo',
                subtitulo: '${ordenados.length} lugares con geocerca: parques, '
                    'Oficina Central y Bodega.',
              ),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < ordenados.length; i++) ...[
                      ListTile(
                        leading: Icon(
                          ordenados[i].activo ? Icons.place_rounded : Icons.location_off_outlined,
                          color: ordenados[i].activo ? null : c.muted,
                        ),
                        title: Text(ordenados[i].nombre,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${centros[ordenados[i].centroCostoId]?.etiqueta ?? 'Sin CECO'}'
                          '${(extras[ordenados[i].id]?.length ?? 0) > 0 ? ' +${extras[ordenados[i].id]!.length} CECO' : ''}'
                          ' · radio ${ordenados[i].radioMetros.round()} m'
                          '${ordenados[i].activo ? '' : ' · INACTIVO'}',
                          style: TextStyle(color: c.muted),
                        ),
                        trailing: const Icon(Icons.edit_rounded),
                        onTap: () => _abrir(context, ref, ordenados[i]),
                      ),
                      if (i < ordenados.length - 1) const Divider(height: 1, indent: 56),
                    ],
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

/// Crear o editar un lugar: datos, centro de costo, geocerca en el mapa y
/// centros adicionales que se pueden cargar ahí.
class LugarEditorPage extends ConsumerStatefulWidget {
  const LugarEditorPage({super.key, this.lugar});

  final Parque? lugar;

  @override
  ConsumerState<LugarEditorPage> createState() => _LugarEditorPageState();
}

class _LugarEditorPageState extends ConsumerState<LugarEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _mapa = MapController();
  late final _nombre = TextEditingController(text: widget.lugar?.nombre);
  late final _codigo = TextEditingController(text: widget.lugar?.codigo);
  late LatLng _centro = widget.lugar == null
      ? const LatLng(14.6349, -90.5069)
      : LatLng(widget.lugar!.latitud, widget.lugar!.longitud);
  late double _radio = (widget.lugar?.radioMetros ?? 150).clamp(30, 1000).toDouble();
  late String? _cecoId = widget.lugar?.centroCostoId;
  late bool _activo = widget.lugar?.activo ?? true;
  bool _guardando = false;

  bool get _nuevo => widget.lugar == null;

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _miUbicacion() async {
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        throw const AppException('Necesitamos tu ubicación para centrar el lugar.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _centro = LatLng(p.latitude, p.longitude));
      _mapa.move(_centro, 17);
    } catch (error) {
      if (mounted) mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final perfil = ref.read(perfilProvider).valueOrNull;
    if (perfil == null) return;
    setState(() => _guardando = true);
    try {
      await ref.read(adminRepositoryProvider).guardarLugar(
            id: widget.lugar?.id,
            empresaId: perfil.empresaId,
            centroCostoId: _cecoId!,
            codigo: _codigo.text,
            nombre: _nombre.text,
            latitud: _centro.latitude,
            longitud: _centro.longitude,
            radioMetros: _radio,
            activo: _activo,
          );
      if (!mounted) return;
      mostrarAviso(context, 'Lugar guardado.', tipo: TipoAviso.success);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
    }
  }

  Future<void> _eliminar() async {
    final lugar = widget.lugar!;
    if (!await confirmar(
      context,
      pregunta: '¿Eliminar ${lugar.nombre}?',
      detalle: 'Si ya tiene jornadas u horarios se desactivará para conservar el historial.',
      aceptar: 'Eliminar',
    )) {
      return;
    }
    try {
      final borrado = await ref.read(adminRepositoryProvider).eliminarLugar(lugar.id);
      if (!mounted) return;
      mostrarAviso(
        context,
        borrado ? 'Lugar eliminado.' : 'Tenía historial: quedó desactivado.',
        tipo: TipoAviso.success,
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
    }
  }

  Future<void> _agregarCeco(List<CentroCosto> centros) async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (hoja) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EncabezadoPagina(
              eyebrow: 'Centros de costo del lugar',
              titulo: 'Agregar centro',
              subtitulo: 'Se podrá cargar en solicitudes de este lugar, junto con sus sub-centros.',
            ),
            SelectorCeco(
              centros: centros,
              onChanged: (valor) => Navigator.of(hoja).pop(valor),
            ),
          ],
        ),
      ),
    );
    if (id == null || perfil == null || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).agregarCentroALugar(
            empresaId: perfil.empresaId,
            lugarId: widget.lugar!.id,
            centroId: id,
          );
      ref.invalidate(centrosPorLugarProvider);
    } catch (error) {
      if (mounted) mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centros = ref.watch(centrosProvider).valueOrNull ?? const <CentroCosto>[];
    final porId = {for (final c in centros) c.id: c};
    final extras = widget.lugar == null
        ? const <String>{}
        : (ref.watch(centrosPorLugarProvider).valueOrNull?[widget.lugar!.id] ?? const <String>{});
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_nuevo ? 'Nuevo lugar' : widget.lugar!.nombre),
        bottom: const FranjaMarca(),
        actions: [
          if (!_nuevo)
            IconButton(
              tooltip: 'Eliminar lugar',
              onPressed: _eliminar,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre del lugar'),
              validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Escribe el nombre.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codigo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código',
                helperText: 'Ej. 057 para un parque, OFC u otro identificador único.',
              ),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Escribe un código.' : null,
            ),
            const SizedBox(height: 12),
            SelectorCeco(
              centros: centrosPrincipales(centros),
              initialValue: _cecoId,
              etiqueta: 'Centro de costo principal',
              onChanged: (v) => setState(() => _cecoId = v),
              validator: (v) => v == null ? 'Elige el centro de costo.' : null,
            ),
            if (!_nuevo)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lugar activo'),
                subtitle: const Text(
                  'Si lo desactivas, nadie puede abrir jornadas aquí; '
                  'el historial se conserva.',
                ),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
            const SizedBox(height: 16),
            Text('Geocerca · radio ${_radio.round()} m',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 260,
                child: FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCenter: _centro,
                    initialZoom: 16,
                    onTap: (_, punto) => setState(() => _centro = punto),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.empresacarrousel.carrousel_app',
                    ),
                    CircleLayer(circles: [
                      CircleMarker(
                        point: _centro,
                        radius: _radio,
                        useRadiusInMeter: true,
                        color: colores.primary.withAlpha(50),
                        borderColor: colores.primary,
                        borderStrokeWidth: 2,
                      ),
                    ]),
                    MarkerLayer(markers: [
                      Marker(
                        point: _centro,
                        width: 36,
                        height: 36,
                        child: Icon(Icons.location_on_rounded, color: colores.primary, size: 36),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            Slider(
              value: _radio,
              min: 30,
              max: 1000,
              divisions: 97,
              label: '${_radio.round()} m',
              onChanged: (v) => setState(() => _radio = v),
            ),
            OutlinedButton.icon(
              onPressed: _miUbicacion,
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('Usar mi ubicación'),
            ),
            if (!_nuevo) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text('Centros de costo adicionales',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  TextButton.icon(
                    onPressed: () => _agregarCeco(centros),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              if (extras.isEmpty)
                const AvisoEnPagina(
                  mensaje: 'Este lugar solo ofrece su centro principal y sus sub-centros.',
                ),
              for (final id in extras)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(porId[id]?.etiqueta ?? 'Centro de costo'),
                  trailing: IconButton(
                    tooltip: 'Quitar',
                    onPressed: () async {
                      try {
                        await ref.read(adminRepositoryProvider).quitarCentroDeLugar(
                              lugarId: widget.lugar!.id,
                              centroId: id,
                            );
                        ref.invalidate(centrosPorLugarProvider);
                      } catch (error) {
                        if (context.mounted) {
                          mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
                        }
                      }
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: const Icon(Icons.save_rounded),
              label: Text(_nuevo ? 'Crear lugar' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}
