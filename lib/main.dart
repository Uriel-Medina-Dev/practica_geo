import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
// El token NO va en el código: se inyecta al compilar con
//   flutter run --dart-define-from-file=dart_defines.json
const String kMapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
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

  Position? _usuario;
  LatLng? _destino;
  double? _distanciaMetros;
  String _direccion = 'Toca el mapa para elegir un destino';
  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciarUbicacion();
  }

  Future<Position> _obtenerUbicacion() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return Future.error('El GPS está desactivado');
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return Future.error('Permiso de ubicación denegado');
    }
    if (perm == LocationPermission.deniedForever) {
      return Future.error('Permiso denegado permanentemente. Actívalo en Ajustes');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _iniciarUbicacion() async {
    try {
      final pos = await _obtenerUbicacion();
      if (!mounted) return;
      setState(() => _usuario = pos);
      _mapController.move(LatLng(pos.latitude, pos.longitude), 16);

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() {
          _usuario = p;
          _recalcularDistancia();
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
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
      final lugares = await Geocoding().placemarkFromCoordinates(punto.latitude, punto.longitude);
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

  @override
  void dispose() {
    _posSub?.cancel();
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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _usuario == null
                          ? 'Ubicación actual: esperando GPS...'
                          : 'Ubicación actual: Lat ${_usuario!.latitude.toStringAsFixed(6)}, '
                              'Lon ${_usuario!.longitude.toStringAsFixed(6)}',
                    ),
                    Text(
                      _destino == null
                          ? 'Punto del mapa: toca un lugar para ver sus coordenadas'
                          : 'Punto del mapa: Lat ${_destino!.latitude.toStringAsFixed(6)}, '
                              'Lon ${_destino!.longitude.toStringAsFixed(6)}',
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
