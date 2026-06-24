import 'package:flutter/material.dart';

import '../models/collection_category.dart';import '../models/user_collection_type.dart';
import '../services/category_hub_preferences.dart';
import '../services/user_collection_type_service.dart';
import '../widgets/app_app_bar.dart';

class CategoryManageScreen extends StatefulWidget {
  const CategoryManageScreen({super.key});

  @override
  State<CategoryManageScreen> createState() => _CategoryManageScreenState();
}

class _CategoryManageScreenState extends State<CategoryManageScreen> {
  final _prefs = CategoryHubPreferences.instance;
  final _customService = UserCollectionTypeService();
  List<UserCollectionType> _customTypes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _prefs.load();
    _customTypes = await _customService.fetchMine();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleCategory(CollectionCategory cat, bool visible) async {
    await _prefs.setVisible(cat, visible);
    setState(() {});
  }

  Future<void> _deleteCustom(UserCollectionType type) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la collection ?'),
        content: Text(
          '« ${type.name} » et tous ses objets seront supprimés définitivement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _customService.deleteWithCleanup(type.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('« ${type.name} » supprimée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Gérer les catégories'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Catégories intégrées',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                ...CollectionCategory.menuValues.map((cat) {
                  return SwitchListTile(
                    secondary: Icon(cat.icon, color: cat.color),
                    title: Text(cat.label),
                    subtitle: Text(cat.description),
                    value: _prefs.isVisible(cat),
                    onChanged: (v) => _toggleCategory(cat, v),
                  );
                }),
                const Divider(height: 32),
                Text(
                  'Collections personnalisées',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (_customTypes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucune collection perso.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                else
                  ..._customTypes.map(
                    (t) => ListTile(
                      leading: Icon(t.icon, color: t.color),
                      title: Text(t.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteCustom(t),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
