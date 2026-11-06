import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors/error_messages.dart';
import '../../core/utils/duraciones.dart';
import '../../core/utils/geo.dart';
import '../../core/widgets/estado_widgets.dart';
import '../../data/models/jornada.dart';
import '../../data/models/parque.dart';
import '../../providers/app_providers.dart';

/// Marcaje de entrada y salida.
///
/// El GPS es nativo y el mapa no permite gestos: solo muestra la ubicación y
/// la geocerca. La validación definitiva ocurre en PostgreSQL, que rechaza
/// cualquier marcaje fuera del parque aunque el cliente sea manipulado.
class MarcajePage extends ConsumerStatefulWidget {
  const MarcajePage({super.key});

  @override
  ConsumerState<MarcajePage> createState() => _MarcajePageState();
}

class _MarcajePageState extends ConsumerState<MarcajePage> {
  final MapController _mapa = MapController();

  Position? _posicion;
  bool _ubicacionCargando = true;
  String? _ubicacionError;
  bool _mapaListo = false;
  bool _enviando = false;
  String? _parqueManualId;

  @override
  void initState() {
    super.initState();
    _actualizarUbicacion();
  }

  Future<void> _actualizarUbicacion() async {
    setState(() {
      _ubicacionCargando = true;
      _ubicacionError = null;
    });

    try {
      final posicion = await _obtenerPosicion();
      if (!mounted) return;
      setState(() {
        _posicion = posicion;
        _ubicacionCargando = false;
      });
      _centrarMapa();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ubicacionError = mensajeDeError(error);
        _ubicacionCargando = false;
      });
    }
  }

  Future<Position> _obtenerPosicion() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      throw const AppException(
        'Activa la ubicación del dispositivo para marcar tu jornada.',
      );
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied) {
      throw const AppException(
        'Necesitamos tu ubicación para comprobar que estás en el parque.',
      );
    }
    if (permiso == LocationPermission.deniedForever) {
      throw const AppException(
        'El permiso de ubicación está bloqueado. Actívalo en los ajustes del dispositivo.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
    } on TimeoutException {
      throw const AppException(
        'El GPS tardó demasiado en responder. Sal al aire libre y reintenta.',
      );
    }
  }

  void _centrarMapa() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapaListo) return;
      final punto = _posicion;
      if (punto == null) return;
      _mapa.move(LatLng(punto.latitude, punto.longitude), 16.5);
    });
  }

  Parque? _parqueObjetivo(
    List<Parque> parques,
    Jornada? abierta,
  ) {
    if (parques.isEmpty) return null;

    // Al cerrar la jornada se usa siempre el parque con el que se abrió.
    if (abierta != null) {
      for (final parque in parques) {
        if (parque.id == abierta.parqueId) return parque;
      }
    }

    if (_parqueManualId != null) {
      for (final parque in parques) {
        if (parque.id == _parqueManualId) return parque;
      }
    }

    final posicion = _posicion;
    if (posicion != null) {
      Parque? cercano;
      var menor = double.infinity;
      for (final parque in parques) {
        final distancia = distanciaMetros(
          posicion.latitude,
          posicion.longitude,
          parque.latitud,
          parque.longitud,
        );
        if (distancia < menor) {
          menor = distancia;
          cercano = parque;
        }
      }
      if (cercano != null) return cercano;
    }

    return parques.first;
  }

  Future<void> _marcar({
    required Parque parque,
    required Jornada? abierta,
  }) async {
    final posicion = _posicion;
    if (posicion == null) {
      await _actualizarUbicacion();
      return;
    }

    if (!_dentroDeGeocerca(parque, posicion)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes estar dentro del área del parque para registrar el marcaje.',
          ),
        ),
      );
      return;
    }

    setState(() => _enviando = true);

    try {
      final repo = ref.read(jornadaRepositoryProvider);
      if (abierta == null) {
        await repo.marcarEntrada(
          parqueId: parque.id,
          latitud: posicion.latitude,
          longitud: posicion.longitude,
          precisionMetros: posicion.accuracy,
        );
      } else {
        await repo.marcarSalida(
          jornadaId: abierta.id,
          latitud: posicion.latitude,
          longitud: posicion.longitude,
          precisionMetros: posicion.accuracy,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              abierta == null
                  ? 'Entrada registrada en ${parque.nombre}.'
                  : 'Salida registrada. Jornada cerrada.',
            ),
          ),
        );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeDeError(error))),
      );
    }
  }

  bool _dentroDeGeocerca(Parque parque, Position posicion) {
    final distancia = distanciaMetros(
      posicion.latitude,
      posicion.longitude,
      parque.latitud,
      parque.longitud,
    );
    return distancia <= parque.radioMetros + toleranciaGps(posicion.accuracy);
  }

  @override
  Widget build(BuildContext context) {
    final jornadas = ref.watch(jornadasStreamProvider).valueOrNull;
    final abierta = jornadas == null ? null : jornadaAbiertaDe(jornadas);
    final parquesAsync = ref.watch(parquesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(abierta == null ? 'Marcar entrada' : 'Marcar salida'),
        actions: [
          IconButton(
            tooltip: 'Actualizar ubicación',
            onPressed: _ubicacionCargando ? null : _actualizarUbicacion,
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: parquesAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando parques...'),
        error: (error, _) => MensajeError(
          mensaje: 'No se pudieron cargar los parques de tu empresa.',
          onReintentar: () => ref.invalidate(parquesProvider),
        ),
        data: (parques) {
          if (parques.isEmpty) {
            return const EstadoVacio(
              icono: Icons.location_off_outlined,
              titulo: 'Sin parques configurados',
              mensaje:
                  'Tu empresa todavía no tiene parques con geocerca. Pide al administrador que los configure.',
            );
          }
          return _contenido(context, parques, abierta);
        },
      ),
    );
  }

  Widget _contenido(
    BuildContext context,
    List<Parque> parques,
    Jornada? abierta,
  ) {
    final colores = Theme.of(context).colorScheme;
    final parque = _parqueObjetivo(parques, abierta);
    final posicion = _posicion;
    final dentro = parque != null &&
        posicion != null &&
        _dentroDeGeocerca(parque, posicion);
    final distancia = parque != null && posicion != null
        ? distanciaMetros(
            posicion.latitude,
            posicion.longitude,
            parque.latitud,
            parque.longitud,
          )
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 300,
            child: _construirMapa(
              parques: parques,
              parque: parque,
              posicion: posicion,
              abierta: abierta,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_ubicacionCargando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                SizedBox(width: 12),
                Text('Obteniendo tu ubicación...'),
              ],
            ),
          )
        else if (_ubicacionError != null)
          _Aviso(
            icono: Icons.location_off_rounded,
            color: colores.errorContainer,
            colorTexto: colores.onErrorContainer,
            titulo: 'Sin ubicación',
            mensaje: _ubicacionError!,
            accion: TextButton(
              onPressed: _actualizarUbicacion,
              child: const Text('Reintentar'),
            ),
          )
        else ...[
          _Aviso(
            icono: dentro ? Icons.check_circle_rounded : Icons.info_rounded,
            color: dentro
                ? colores.primaryContainer
                : colores.tertiaryContainer,
            colorTexto: dentro
                ? colores.onPrimaryContainer
                : colores.onTertiaryContainer,
            titulo: parque?.nombre ?? 'Parque',
            mensaje: distancia == null
                ? 'Selecciona el parque donde te encuentras.'
                : dentro
                    ? 'Estás dentro de la geocerca. Precisión GPS: '
                        '${posicion.accuracy.toStringAsFixed(0)} m.'
                    : 'Estás a ${distancia.toStringAsFixed(0)} m del parque '
                        '(radio ${parque!.radioMetros.toStringAsFixed(0)} m). '
                        'Acércate para poder marcar.',
          ),
        ],
        if (abierta != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colores.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colores.outlineVariant, width: 0.6),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, color: colores.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Jornada abierta',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Entrada ${formatearHora(abierta.entradaEn)} · '
                        '${formatearDuracion(abierta.duracionHasta(DateTime.now()))}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colores.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (abierta == null && parques.length > 1) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey('parque-${parque?.id}'),
            initialValue: parque?.id,
            decoration: const InputDecoration(
              labelText: 'Parque donde trabajas',
              prefixIcon: Icon(Icons.attractions_outlined),
            ),
            items: [
              for (final item in parques)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(item.nombre),
                ),
            ],
            onChanged: (valor) => setState(() => _parqueManualId = valor),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _enviando || parque == null || !dentro
              ? null
              : () => _marcar(parque: parque, abierta: abierta),
          icon: _enviando
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Icon(
                  abierta == null
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                ),
          label: Text(
            abierta == null ? 'Registrar entrada' : 'Registrar salida',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'El marcaje se valida contra la geocerca del parque. '
          'El mapa es solo informativo y no permite mover ni ampliar la zona.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colores.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _construirMapa({
    required List<Parque> parques,
    required Parque? parque,
    required Position? posicion,
    required Jornada? abierta,
  }) {
    final centro = posicion != null
        ? LatLng(posicion.latitude, posicion.longitude)
        : parque != null
            ? LatLng(parque.latitud, parque.longitud)
            : const LatLng(10.4806, -66.9036);

    return FlutterMap(
      mapController: _mapa,
      options: MapOptions(
        initialCenter: centro,
        initialZoom: 16,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
        onMapReady: () => _mapaListo = true,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.empresacarrousel.carrousel_app',
        ),
        CircleLayer(
          circles: [
            for (final item in parques)
              CircleMarker(
                point: LatLng(item.latitud, item.longitud),
                radius: item.radioMetros,
                useRadiusInMeter: true,
                color: item.id == parque?.id
                    ? const Color(0x330F766E)
                    : const Color(0x1A0F766E),
                borderColor: item.id == parque?.id
                    ? const Color(0xCC0F766E)
                    : const Color(0x660F766E),
                borderStrokeWidth: 2,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final item in parques)
              Marker(
                point: LatLng(item.latitud, item.longitud),
                width: 40,
                height: 40,
                child: Icon(
                  Icons.attractions_rounded,
                  size: 34,
                  color: item.id == parque?.id
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF64748B),
                ),
              ),
            if (posicion != null)
              Marker(
                point: LatLng(posicion.latitude, posicion.longitude),
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x552563EB),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icono,
    required this.color,
    required this.colorTexto,
    required this.titulo,
    required this.mensaje,
    this.accion,
  });

  final IconData icono;
  final Color color;
  final Color colorTexto;
  final String titulo;
  final String mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: colorTexto),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colorTexto,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mensaje,
                  style: TextStyle(color: colorTexto, fontSize: 13),
                ),
                ?accion,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
