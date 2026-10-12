import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/supabase_embeds.dart';

/// Exporte une sélection de la collection / wishlist (CSV ou texte web).
class CollectionShareScreen extends StatefulWidget {
  const CollectionShareScreen({super.key});

  @override
  State<CollectionShareScreen> createState() => _CollectionShareScreenState();
}

class _CollectionShareScreenState extends State<CollectionShareScreen> {
  bool _loading = true;
  List<CollectionItem> _items = [];
  final _selectedCategories = <CollectionCategory>{
    ...CollectionCategory.values,
  };
  bool _includeCollection = true;
  bool _includeWishlist = true;
  bool _includeImages = false;
  final _excludedIds = <String>{};
  String _format = 'csv'; // csv | web

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Non connecté');
      final rows = await Supabase.instance.client
          .from('collection_items')
          .select(SupabaseEmbeds.collectionItemList)
          .or('added_by.eq.$uid,location_user_id.eq.$uid')
          .order('title');
      final items = (rows as List)
          .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
          .where((i) => !i.isSold)
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  List<CollectionItem> get _visible {
    return _items.where((i) {
      if (!_selectedCategories.contains(i.category)) return false;
      if (i.isWishlist && !_includeWishlist) return false;
      if (!i.isWishlist && !_includeCollection) return false;
      if (_excludedIds.contains(i.id)) return false;
      return true;
    }).toList();
  }

  String _buildCsv() {
    final buf = StringBuffer();
    buf.writeln(
      _includeImages
          ? 'Titre;Catégorie;Type;Image'
          : 'Titre;Catégorie;Type',
    );
    for (final i in _visible) {
      final type = i.isWishlist ? 'Wishlist' : 'Collection';
      final title = i.title.replaceAll(';', ',');
      if (_includeImages) {
        buf.writeln('$title;${i.category.label};$type;${i.imageUrl ?? ''}');
      } else {
        buf.writeln('$title;${i.category.label};$type');
      }
    }
    return buf.toString();
  }

  String _buildHtml() {
    final rows = _visible.map((i) {
      final type = i.isWishlist ? 'Wishlist' : 'Collection';
      final img = _includeImages && i.imageUrl != null
          ? '<td><img src="${i.imageUrl}" height="40"/></td>'
          : '';
      return '<tr><td>${i.title}</td><td>${i.category.label}</td><td>$type</td>$img</tr>';
    }).join();
    final imgHeader = _includeImages ? '<th>Image</th>' : '';
    return '''<!DOCTYPE html><html><head><meta charset="utf-8"><title>Ma collection</title>
<style>body{font-family:sans-serif;padding:24px}table{border-collapse:collapse;width:100%}
td,th{border:1px solid #ccc;padding:8px;text-align:left}</style></head><body>
<h1>Ma collection</h1>
<table><thead><tr><th>Titre</th><th>Catégorie</th><th>Type</th>$imgHeader</tr></thead>
<tbody>$rows</tbody></table></body></html>''';
  }

  Future<void> _export() async {
    final text = _format == 'web' ? _buildHtml() : _buildCsv();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _format == 'web'
              ? 'Page web copiée (${_visible.length} objets) — colle dans un fichier .html'
              : 'CSV copié (${_visible.length} objets) — colle dans Excel',
        ),
      ),
    );
  }

  Future<void> _pickExclusions() async {
    final q = TextEditingController();
    final selected = Set<String>.from(_excludedIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final query = q.text.trim().toLowerCase();
            final pool = _items.where((i) {
              if (!_selectedCategories.contains(i.category)) return false;
              if (query.isEmpty) return true;
              return i.title.toLowerCase().contains(query);
            }).take(80).toList();
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: q,
                      decoration: const InputDecoration(
                        labelText: 'Ne pas montrer…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setSheet(() {}),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: pool.length,
                      itemBuilder: (context, index) {
                        final item = pool[index];
                        final excluded = selected.contains(item.id);
                        return CheckboxListTile(
                          value: excluded,
                          title: Text(item.title),
                          subtitle: Text(
                            item.isWishlist ? 'Wishlist' : 'Collection',
                          ),
                          onChanged: (v) {
                            setSheet(() {
                              if (v == true) {
                                selected.add(item.id);
                              } else {
                                selected.remove(item.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _excludedIds
                            ..clear()
                            ..addAll(selected);
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('OK'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    q.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partage')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Choisis ce que tu partages',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in CollectionCategory.values)
                      FilterChip(
                        label: Text(c.label),
                        selected: _selectedCategories.contains(c),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedCategories.add(c);
                          } else {
                            _selectedCategories.remove(c);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Collection'),
                  value: _includeCollection,
                  onChanged: (v) => setState(() => _includeCollection = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Wishlist'),
                  value: _includeWishlist,
                  onChanged: (v) => setState(() => _includeWishlist = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inclure les images'),
                  subtitle: const Text('Non par défaut'),
                  value: _includeImages,
                  onChanged: (v) => setState(() => _includeImages = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Ne pas montrer…'),
                  subtitle: Text(
                    _excludedIds.isEmpty
                        ? 'Aucun objet masqué'
                        : '${_excludedIds.length} masqué(s)',
                  ),
                  trailing: const Icon(Icons.search),
                  onTap: _pickExclusions,
                ),
                const SizedBox(height: 8),
                Text('Format', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'csv', label: Text('Excel (CSV)')),
                    ButtonSegment(value: 'web', label: Text('Page web')),
                  ],
                  selected: {_format},
                  onSelectionChanged: (s) => setState(() => _format = s.first),
                ),
                const SizedBox(height: 20),
                Text(
                  '${_visible.length} objet(s) seront exportés',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _visible.isEmpty ? null : _export,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copier l\'export'),
                ),
              ],
            ),
    );
  }
}
