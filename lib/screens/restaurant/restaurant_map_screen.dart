import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/restaurant_visit.dart';
import '../../services/group_service.dart';
import '../../services/restaurant_service.dart';

class RestaurantMapScreen extends StatefulWidget {
  const RestaurantMapScreen({super.key});

  @override
  State<RestaurantMapScreen> createState() => _RestaurantMapScreenState();
}

class _RestaurantMapScreenState extends State<RestaurantMapScreen> {
  final _service = RestaurantService();
  final _groups = GroupService();
  List<RestaurantVisit> _visits = [];
  List<(String, String)> _groupChoices = [];
  String? _groupId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final groups = await _groups.fetchMyGroups();
    _groupChoices = groups.map((g) => (g.id, g.name)).toList();
    await _reloadVisits();
  }

  Future<void> _reloadVisits() async {
    setState(() => _loading = true);
    if (_groupId != null) {
      _visits = await _service.fetchGroupMapVisits(_groupId!);
    } else {
      _visits = await _service.fetchMyMapVisits();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final center = _visits.isNotEmpty
        ? LatLng(_visits.first.latitude!, _visits.first.longitude!)
        : const LatLng(48.85, 2.35);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte culinaire'),
        actions: [
          if (_groupChoices.isNotEmpty)
            PopupMenuButton<String?>(
              icon: const Icon(Icons.groups),
              initialValue: _groupId,
              onSelected: (id) {
                _groupId = id;
                _reloadVisits();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: null, child: Text('Ma carte')),
                ..._groupChoices.map(
                  (g) => PopupMenuItem(value: g.$1, child: Text(g.$2)),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: _visits.length == 1 ? 12 : 5,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.collectingo.app',
                ),
                MarkerLayer(
                  markers: [
                    for (final v in _visits)
                      Marker(
                        point: LatLng(v.latitude!, v.longitude!),
                        width: 36,
                        height: 36,
                        child: const Icon(
                          Icons.restaurant,
                          color: Color(0xFFD84315),
                          size: 30,
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
