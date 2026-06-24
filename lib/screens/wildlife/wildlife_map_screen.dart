import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/wildlife_observation.dart';
import '../../services/wildlife_service.dart';

class WildlifeMapScreen extends StatefulWidget {
  const WildlifeMapScreen({super.key});

  @override
  State<WildlifeMapScreen> createState() => _WildlifeMapScreenState();
}

class _WildlifeMapScreenState extends State<WildlifeMapScreen> {
  final _service = WildlifeService();
  List<WildlifeObservation> _points = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _points = await _service.fetchAllForMap();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
  final center = _points.isNotEmpty
      ? LatLng(_points.first.latitude!, _points.first.longitude!)
      : const LatLng(46.5, 2.5);

    return Scaffold(
      appBar: AppBar(title: const Text('Carte sauvage')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: _points.length == 1 ? 10 : 5,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.collectingo.app',
                ),
                MarkerLayer(
                  markers: [
                    for (final o in _points)
                      Marker(
                        point: LatLng(o.latitude!, o.longitude!),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.pets,
                          color: Color(0xFF2E7D32),
                          size: 32,
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
