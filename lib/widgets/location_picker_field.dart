import 'package:flutter/material.dart';
import '../models/storage_location.dart';
import '../services/location_service.dart';
import '../utils/search_relevance.dart';

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
  final _searchController = TextEditingController();
  List<StorageLocation> _locations = [];
  List<StorageLocation> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filter);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LocationPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) {
      _searchController.clear();
      setState(() => _loading = true);
      _load();
    }
  }

  Future<void> _load() async {
    final list = await _service.fetchLocations(groupId: widget.groupId);
    if (!mounted) return;

    StorageLocation? selected;
    if (widget.selectedLocationId != null) {
      for (final l in list) {
        if (l.id == widget.selectedLocationId) {
          selected = l;
          break;
        }
      }
    }

    setState(() {
      _locations = list;
      _loading = false;
      if (selected != null) {
        _searchController.text = selected.label;
      } else if (widget.selectedLocationId != null) {
        _searchController.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onChanged(null);
        });
      }
    });
    _filter();
  }

  void _filter() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(_locations);
      } else {
        _filtered = _locations
            .where((l) => titleRelevanceScore(l.label, q) > 0)
            .toList();
        sortByScore(
          _filtered,
          (l) => titleRelevanceScore(l.label, q),
        );
      }
    });
  }

  Future<void> _addNew(String label) async {
    if (label.trim().isEmpty) return;
    final created = await _service.createLocation(
      label: label.trim(),
      groupId: widget.groupId,
    );
    await _load();
    _searchController.text = created.label;
    widget.onChanged(created);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator();
    }

    final query = _searchController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Où se trouve l\'objet ?',
            hintText: 'Tape « pa » → Chez Papa…',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.place_outlined),
          ),
        ),
        if (query.isNotEmpty && _filtered.isEmpty)
          ListTile(
            leading: const Icon(Icons.add_location_alt),
            title: Text('Créer « $query »'),
            onTap: () => _addNew(query),
          ),
        if (_filtered.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final loc = _filtered[index];
                final selected = loc.id == widget.selectedLocationId;
                return ListTile(
                  dense: true,
                  selected: selected,
                  title: Text(loc.label),
                  trailing: selected ? const Icon(Icons.check, size: 18) : null,
                  onTap: () {
                    _searchController.text = loc.label;
                    widget.onChanged(loc);
                  },
                );
              },
            ),
          ),
        TextButton.icon(
          onPressed: () async {
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
            if (label != null && label.isNotEmpty) await _addNew(label);
          },
          icon: const Icon(Icons.add_location_alt),
          label: const Text('Ajouter une localisation'),
        ),
        if (widget.selectedLocationId != null)
          TextButton(
            onPressed: () {
              _searchController.clear();
              widget.onChanged(null);
            },
            child: const Text('Effacer la localisation'),
          ),
      ],
    );
  }
}
