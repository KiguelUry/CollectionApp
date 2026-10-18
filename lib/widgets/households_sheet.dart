import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/household_service.dart';
import '../services/social_directory_cache.dart';
import '../utils/holder_label_utils.dart';

/// Gestionnaire Lieux ↔ Personnes + liaisons de foyers.
Future<void> showHouseholdsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _HouseholdsSheet(),
  );
}

class _HouseholdsSheet extends StatefulWidget {
  const _HouseholdsSheet();

  @override
  State<_HouseholdsSheet> createState() => _HouseholdsSheetState();
}

class _HouseholdsSheetState extends State<_HouseholdsSheet> {
  List<Household> _homes = [];
  final _places = <({String name, PlacePrefix prefix})>[];
  final _people = <String>[];
  String? _selectedPlace;
  final _selectedPeople = <String>{};
  bool _preferChezMoi = false;
  bool _loading = false;
  final PlacePrefix _newPlacePrefix = PlacePrefix.a;

  @override
  void initState() {
    super.initState();
    _seedFromCache();
    unawaited(_load());
  }

  void _seedFromCache() {
    final cache = SocialDirectoryCache.instance;
    final places = <String, PlacePrefix>{};
    final people = <String>{};
    for (final home in HouseholdService.instance.homes) {
      places[home.place] = home.placePrefix;
      people.addAll(home.people);
    }
    for (final place in cache.places) {
      places.putIfAbsent(place, () => PlacePrefix.a);
    }
    people.addAll(cache.people);
    _homes = [...HouseholdService.instance.homes];
    _places.addAll([
      for (final e in places.entries) (name: e.key, prefix: e.value),
    ]);
    _people.addAll(people.toList()..sort());
  }

  Future<void> _load() async {
    await HouseholdService.instance.ensureLoaded();
    if (!SocialDirectoryCache.instance.ready) {
      await SocialDirectoryCache.instance.warm();
    }
    final homes = [...HouseholdService.instance.homes];
    final places = <String, PlacePrefix>{};
    final people = <String>{};
    for (final home in homes) {
      places[home.place] = home.placePrefix;
      people.addAll(home.people);
    }
    for (final place in SocialDirectoryCache.instance.places) {
      places.putIfAbsent(place, () => PlacePrefix.a);
    }
    people.addAll(SocialDirectoryCache.instance.people);
    try {
      final friends = await FriendService().fetchFriends();
      for (final f in friends) {
        final name = f['username']?.toString();
        if (name != null && name.isNotEmpty) people.add(name);
      }
      final groups = await GroupService().fetchMyGroups();
      for (final g in groups) {
        final members = await GroupService().fetchMembers(g.id);
        for (final m in members) {
          final profile = m['profiles'] ?? m['profile'];
          final name = profile is Map
              ? profile['username']?.toString()
              : m['username']?.toString();
          if (name != null && name.isNotEmpty) people.add(name);
        }
      }
    } catch (_) {}
    final me = Supabase.instance.client.auth.currentUser;
    final aliases = HouseholdService.instance.myAliases;
    for (final a in aliases) {
      people.add(a);
    }
    if (me != null) {
      try {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('username')
            .eq('id', me.id)
            .maybeSingle();
        final username = row?['username']?.toString();
        if (username != null && username.isNotEmpty) people.add(username);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _homes = homes;
      _places
        ..clear()
        ..addAll([
          for (final e in places.entries) (name: e.key, prefix: e.value),
        ]);
      _people
        ..clear()
        ..addAll(people.toList()..sort());
      _loading = false;
    });
  }

  Future<void> _persistHomes() async {
    await HouseholdService.instance.save(_homes);
  }

  void _selectPlace(String place) {
    final home = _homes.cast<Household?>().firstWhere(
          (h) => h!.place == place,
          orElse: () => null,
        );
    setState(() {
      _selectedPlace = place;
      _selectedPeople
        ..clear()
        ..addAll(home?.people ?? const []);
      _preferChezMoi = home?.preferChezMoi ?? false;
    });
  }

  Future<void> _linkSelection() async {
    final place = _selectedPlace;
    if (place == null || place.isEmpty) return;
    final prefix = _places
            .cast<({String name, PlacePrefix prefix})?>()
            .firstWhere((p) => p!.name == place, orElse: () => null)
            ?.prefix ??
        PlacePrefix.a;
    final existingIdx = _homes.indexWhere((h) => h.place == place);
    final home = Household(
      id: existingIdx >= 0
          ? _homes[existingIdx].id
          : 'h${DateTime.now().microsecondsSinceEpoch}',
      place: place,
      placePrefix: prefix,
      people: _selectedPeople.toList()..sort(),
      preferChezMoi: _preferChezMoi,
    );
    setState(() {
      if (existingIdx >= 0) {
        _homes[existingIdx] = home;
      } else {
        _homes = [..._homes, home];
      }
    });
    await _persistHomes();
  }

  Future<void> _addPlace() async {
    final ctrl = TextEditingController();
    var prefix = _newPlacePrefix;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nouveau lieu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<PlacePrefix>(
                segments: [
                  for (final p in PlacePrefix.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {prefix},
                onSelectionChanged: (v) => setLocal(() => prefix = v.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom du lieu',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || name.isEmpty || !mounted) return;
    setState(() {
      if (!_places.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
        _places.add((name: name, prefix: prefix));
      }
      _selectedPlace = name;
      _selectedPeople.clear();
      _preferChezMoi = false;
    });
  }

  Future<void> _addPerson() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle personne'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || name.isEmpty || !mounted) return;
    setState(() {
      if (!_people.any((p) => p.toLowerCase() == name.toLowerCase())) {
        _people.add(name);
        _people.sort();
      }
    });
  }

  void _moveToPlaces(String person) {
    setState(() {
      _people.removeWhere((p) => p == person);
      if (!_places.any((p) => p.name.toLowerCase() == person.toLowerCase())) {
        _places.add((name: person, prefix: PlacePrefix.a));
      }
      _selectedPeople.remove(person);
    });
  }

  void _moveToPeople(String place) {
    setState(() {
      _places.removeWhere((p) => p.name == place);
      if (!_people.any((p) => p.toLowerCase() == place.toLowerCase())) {
        _people.add(place);
        _people.sort();
      }
      if (_selectedPlace == place) {
        _selectedPlace = null;
        _selectedPeople.clear();
      }
      _homes = [for (final h in _homes) if (h.place != place) h];
    });
    unawaited(_persistHomes());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Foyers & lieux liés',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Lie un lieu à des personnes. Chez toi, le foyer peut s\'afficher '
              '« Chez moi » ; chez les autres, c\'est le lieu.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _placesColumn()),
                  const SizedBox(width: 10),
                  Expanded(child: _peopleColumn()),
                ],
              ),
            ),
            if (_selectedPlace != null) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Chez moi, afficher « Chez moi »'),
                subtitle: Text('Sinon : ${_selectedPlaceLabel()}'),
                value: _preferChezMoi,
                onChanged: (v) => setState(() => _preferChezMoi = v),
              ),
              FilledButton.icon(
                onPressed: _linkSelection,
                icon: const Icon(Icons.link),
                label: Text(
                  'Lier ${_selectedPeople.length} personne(s) à $_selectedPlace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _selectedPlaceLabel() {
    final p = _places.cast<({String name, PlacePrefix prefix})?>().firstWhere(
          (e) => e!.name == _selectedPlace,
          orElse: () => null,
        );
    if (p == null) return 'À $_selectedPlace';
    return '${p.prefix.label} ${p.name}';
  }

  Widget _placesColumn() {
    return _columnCard(
      title: '📍 Lieux',
      onAdd: _addPlace,
      child: ListView(
        children: [
          for (final place in _places)
            DragTarget<String>(
              onWillAcceptWithDetails: (d) => d.data.startsWith('person:'),
              onAcceptWithDetails: (d) {
                final name = d.data.substring('person:'.length);
                _moveToPlaces(name);
              },
              builder: (context, candidate, _) {
                final selected = _selectedPlace == place.name;
                return LongPressDraggable<String>(
                  data: 'place:${place.name}',
                  feedback: Material(
                    elevation: 4,
                    child: Chip(label: Text('${place.prefix.label} ${place.name}')),
                  ),
                  child: ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor:
                        Colors.teal.withValues(alpha: candidate.isEmpty ? 0.12 : 0.28),
                    title: Text('${place.prefix.label} ${place.name}'),
                    trailing: PopupMenuButton<PlacePrefix>(
                      tooltip: 'Préfixe',
                      onSelected: (pref) {
                        setState(() {
                          final i = _places.indexWhere((p) => p.name == place.name);
                          if (i >= 0) {
                            _places[i] = (name: place.name, prefix: pref);
                          }
                          final hi = _homes.indexWhere((h) => h.place == place.name);
                          if (hi >= 0) {
                            _homes[hi] = _homes[hi].copyWith(placePrefix: pref);
                          }
                        });
                        unawaited(_persistHomes());
                      },
                      itemBuilder: (_) => [
                        for (final p in PlacePrefix.values)
                          PopupMenuItem(value: p, child: Text(p.label)),
                      ],
                      child: Text(
                        place.prefix.label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    onTap: () => _selectPlace(place.name),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _peopleColumn() {
    return _columnCard(
      title: '👤 Personnes',
      onAdd: _addPerson,
      child: ListView(
        children: [
          for (final person in _people)
            DragTarget<String>(
              onWillAcceptWithDetails: (d) => d.data.startsWith('place:'),
              onAcceptWithDetails: (d) {
                final name = d.data.substring('place:'.length);
                _moveToPeople(name);
              },
              builder: (context, candidate, _) {
                final selected = _selectedPeople.contains(person);
                return LongPressDraggable<String>(
                  data: 'person:$person',
                  feedback: Material(
                    elevation: 4,
                    child: Chip(label: Text(person)),
                  ),
                  child: CheckboxListTile(
                    dense: true,
                    value: selected,
                    title: Text(formatManualHolderLabel(
                      person,
                      kind: ManualHolderKind.person,
                    )),
                    tileColor: candidate.isEmpty
                        ? null
                        : Colors.teal.withValues(alpha: 0.16),
                    onChanged: _selectedPlace == null
                        ? null
                        : (v) {
                            setState(() {
                              if (v == true) {
                                _selectedPeople.add(person);
                              } else {
                                _selectedPeople.remove(person);
                              }
                            });
                          },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _columnCard({
    required String title,
    required VoidCallback onAdd,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Ajouter',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
