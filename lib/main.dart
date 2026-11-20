import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// El token NO va en el código: se inyecta al compilar con
//   flutter run --dart-define-from-file=dart_defines.json
const String kMapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

class CachedTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(
      url,
      headers: headers,
      cacheManager: CachedNetworkImageProvider.defaultCacheManager,
    );
  }
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Localizador',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const MapaPage(),
    );
  }
}

class MapaPage extends StatefulWidget {
  const MapaPage({super.key});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  static const LatLng _utxj = LatLng(20.2756, -97.9611);

  final MapController _mapController = MapController();
  StreamSubscription<Position>? _posSub;
  Timer? _seguimientoTimer;
  LatLng? _objetivoSeguimiento;

  Position? _usuario;
  LatLng? _puntoGpsEnMapa;
  DateTime? _ultimaActualizacionGps;
  LatLng? _destino;
  double? _distanciaMetros;
  String _direccion = 'Toca el mapa para elegir un destino';
  String? _error;
  bool _descargandoMapa = false;
  String _estadoDescarga = '';
  final BaseCacheManager _cacheManager = DefaultCacheManager();

  @override
  void initState() {
    super.initState();
    _iniciarUbicacion();
  }

  Future<Position> _obtenerUbicacion() async {
    await _comprobarPermisoUbicacion();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _comprobarPermisoUbicacion() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'El GPS está desactivado';
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw 'Permiso de ubicación denegado';
    }
    if (perm == LocationPermission.deniedForever) {
      throw 'Permiso denegado permanentemente. Actívalo en Ajustes';
    }
  }

  Future<void> _iniciarUbicacion() async {
    try {
      await _comprobarPermisoUbicacion();
      if (!mounted) return;

      _posSub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(milliseconds: 500),
          maxUpdateAge: const Duration(seconds: 2),
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() {
          _usuario = p;
          _puntoGpsEnMapa = LatLng(p.latitude, p.longitude);
          _ultimaActualizacionGps = DateTime.now();
          _recalcularDistancia();
        });
        _animarSeguimiento(_puntoGpsEnMapa!);
      });

      final pos = await _obtenerUbicacion();
      if (!mounted) return;
      setState(() {
        _usuario = pos;
        _puntoGpsEnMapa = LatLng(pos.latitude, pos.longitude);
        _ultimaActualizacionGps = DateTime.now();
        _recalcularDistancia();
      });
      _mapController.move(_puntoGpsEnMapa!, 16);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _animarSeguimiento(LatLng destino) {
    _objetivoSeguimiento = destino;
    _seguimientoTimer?.cancel();

    final origen = _mapController.camera.center;
    const duracion = Duration(milliseconds: 300);
    const frecuencia = Duration(milliseconds: 16);
    final inicio = DateTime.now();

    _seguimientoTimer = Timer.periodic(frecuencia, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final transcurrido = DateTime.now().difference(inicio).inMilliseconds;
      final progreso = (transcurrido / duracion.inMilliseconds).clamp(0.0, 1.0);
      final suave = Curves.easeOut.transform(progreso);
      final objetivo = _objetivoSeguimiento;
      if (objetivo == null) {
        timer.cancel();
        return;
      }

      _mapController.move(
        LatLng(
          origen.latitude + (objetivo.latitude - origen.latitude) * suave,
          origen.longitude + (objetivo.longitude - origen.longitude) * suave,
        ),
        _mapController.camera.zoom,
      );

      if (progreso >= 1) timer.cancel();
    });
  }

  void _recalcularDistancia() {
    final u = _usuario;
    final d = _destino;
    if (u == null || d == null) return;
    _distanciaMetros = Geolocator.distanceBetween(
        u.latitude, u.longitude, d.latitude, d.longitude);
  }

  Future<void> _onTapMapa(TapPosition _, LatLng punto) async {
    setState(() {
      _destino = punto;
      _direccion = 'Buscando dirección...';
      _recalcularDistancia();
    });
    try {
      final lugares = await Geocoding()
          .placemarkFromCoordinates(punto.latitude, punto.longitude);
      final l = lugares.first;
      final partes = [
        if ((l.street ?? '').isNotEmpty) l.street!,
        if ((l.subLocality ?? '').isNotEmpty) 'Col. ${l.subLocality}',
        if ((l.locality ?? '').isNotEmpty) l.locality!,
      ];
      if (!mounted) return;
      setState(() => _direccion =
          partes.isEmpty ? 'Sin dirección disponible' : partes.join(', '));
    } catch (_) {
      if (!mounted) return;
      setState(() => _direccion = 'No se pudo obtener la dirección');
    }
  }

  Future<void> _descargarZonaVisible() async {
    if (kMapboxToken.isEmpty) return;

    setState(() {
      _descargandoMapa = true;
      _estadoDescarga = 'Descargando zona...';
    });

    try {
      final bounds = _mapController.camera.visibleBounds;
      const zoom = 15;
      final minX = _tileX(bounds.west, zoom);
      final maxX = _tileX(bounds.east, zoom);
      final minY = _tileY(bounds.north, zoom);
      final maxY = _tileY(bounds.south, zoom);

      var descargados = 0;
      var pendientes = <Future<void>>[];

      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          final url =
              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/$zoom/$x/$y@2x'
              '?access_token=$kMapboxToken';

          pendientes.add(
            _cacheManager.downloadFile(url).then((_) {
              descargados++;
            }),
          );

          if (pendientes.length >= 8) {
            await Future.wait(pendientes);
            pendientes = <Future<void>>[];
            if (mounted) {
              setState(() =>
                  _estadoDescarga = 'Descargando zona... $descargados tiles');
            }
          }
        }
      }

      await Future.wait(pendientes);
      if (!mounted) return;
      setState(() {
        _descargandoMapa = false;
        _estadoDescarga = 'Zona descargada: $descargados tiles';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _descargandoMapa = false;
        _estadoDescarga = 'No se pudo descargar la zona';
      });
    }
  }

  int _tileX(double longitude, int zoom) {
    final n = 1 << zoom;
    return ((longitude + 180) / 360 * n).floor();
  }

  int _tileY(double latitude, int zoom) {
    final latRad = latitude * math.pi / 180;
    final n = 1 << zoom;
    return ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            n)
        .floor();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _seguimientoTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (_usuario != null)
        Marker(
          point: LatLng(_usuario!.latitude, _usuario!.longitude),
          width: 28,
          height: 28,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 28),
        ),
      if (_destino != null)
        Marker(
          point: _destino!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
        ),
    ];

    if (kMapboxToken.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Falta el token de Mapbox.\nEjecuta:\nflutter run --dart-define-from-file=dart_defines.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Localizador')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _utxj,
              initialZoom: 15.5,
              onTap: _onTapMapa,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
                additionalOptions: const {'accessToken': kMapboxToken},
                userAgentPackageName: 'com.example.practica_geo',
                tileProvider: CachedTileProvider(),
              ),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© Mapbox'),
                  TextSourceAttribution('© OpenStreetMap'),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            right: 12,
            child: FloatingActionButton.small(
              tooltip: 'Descargar zona visible',
              onPressed: _descargandoMapa ? null : _descargarZonaVisible,
              child: _descargandoMapa
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
            ),
          ),
          if (_estadoDescarga.isNotEmpty)
            Positioned(
              top: 64,
              right: 12,
              child: Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(_estadoDescarga),
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    Text(
                      _distanciaMetros == null
                          ? 'Distancia: --'
                          : 'Distancia: ${_distanciaMetros!.toStringAsFixed(0)} m',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _usuario == null
                          ? 'Ubicación actual: esperando GPS...'
                          : 'Ubicación actual: Lat ${_usuario!.latitude.toStringAsFixed(4)}, '
                              'Lon ${_usuario!.longitude.toStringAsFixed(6)}',
                    ),
                    Text(
                      _destino == null
                          ? 'Destino: no seleccionado'
                          : 'Destino: Lat ${_destino!.latitude.toStringAsFixed(4)}, '
                              'Lon ${_destino!.longitude.toStringAsFixed(6)}',
                    ),
                    if (_ultimaActualizacionGps != null)
                      Text(
                        'Última actualización GPS: ${_ultimaActualizacionGps!.hour.toString().padLeft(2, '0')}:'
                        '${_ultimaActualizacionGps!.minute.toString().padLeft(2, '0')}:'
                        '${_ultimaActualizacionGps!.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    Text(_direccion),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
