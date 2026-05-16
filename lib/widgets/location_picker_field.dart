import 'package:flutter/material.dart';
import '../models/storage_location.dart';
import '../services/location_service.dart';

class LocationPickerField extends StatefulWidget {
  final String? selectedLocationId;
  final String? groupId;
  final ValueChanged<StorageLocation?> onChanged;

  const LocationPickerField({
    super.key,
    required this.selectedLocationId,
    required this.onChanged,
    this.groupId,
  });

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  final _service = LocationService();
  List<StorageLocation> _locations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.fetchLocations(groupId: widget.groupId);
    if (mounted) {
      setState(() {
        _locations = list;
        _loading = false;
      });
    }
  }

  Future<void> _addNew() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle localisation'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nom',
            hintText: 'ex: Chez Papa',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;

    final created = await _service.createLocation(
      label: label,
      groupId: widget.groupId,
    );
    await _load();
    widget.onChanged(created);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          value: widget.selectedLocationId,
          decoration: const InputDecoration(
            labelText: 'Où se trouve l\'objet ?',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('— Non renseigné —'),
            ),
            ..._locations.map(
              (l) => DropdownMenuItem(value: l.id, child: Text(l.label)),
            ),
          ],
          onChanged: (id) {
            if (id == null) {
              widget.onChanged(null);
              return;
            }
            widget.onChanged(_locations.firstWhere((l) => l.id == id));
          },
        ),
        TextButton.icon(
          onPressed: _addNew,
          icon: const Icon(Icons.add_location_alt),
          label: const Text('Ajouter une localisation'),
        ),
      ],
    );
  }
}
