import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../widgets/main_drawer.dart';
import 'home_screen.dart';

class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() =>
      _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  Map<CollectionCategory, int> _counts = {};
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<String> _getUsername() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 'Aventurier';

    final data = await Supabase.instance.client
        .from('profiles')
        .select('username')
        .eq('id', user.id)
        .single();
    return data['username'] ?? 'Aventurier';
  }

  Future<void> _loadCounts() async {
    final rows = await Supabase.instance.client
        .from('collection_items')
        .select('category')
        .eq('is_wishlist', false);

    final counts = {
      for (final c in CollectionCategory.values) c: 0,
    };
    for (final row in rows) {
      final cat = CollectionCategory.fromDbValue(row['category'] as String);
      counts[cat] = (counts[cat] ?? 0) + 1;
    }

    if (mounted) {
      setState(() {
        _counts = counts;
        _loadingCounts = false;
      });
    }
  }

  void _openCategory(CollectionCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(category: category),
      ),
    ).then((_) => _loadCounts());
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma Collection Famille'),
      ),
      drawer: const MainDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String>(
              future: _getUsername(),
              builder: (context, snapshot) {
                final name = snapshot.data ?? '...';
                return Text(
                  'Salut $name !',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
            const Text(
              'Quelle collection veux-tu consulter ?',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _loadingCounts
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 15,
                      children: CollectionCategory.values
                          .map((category) => _buildCategoryCard(category))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(CollectionCategory category) {
    final count = _counts[category] ?? 0;
    final countLabel = count == 0
        ? 'Vide'
        : count == 1
            ? '1 objet'
            : '$count objets';

    return InkWell(
      onTap: () => _openCategory(category),
      borderRadius: BorderRadius.circular(20),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: category.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(category.icon, size: 40, color: category.color),
            ),
            const SizedBox(height: 12),
            Text(
              category.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                category.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              countLabel,
              style: TextStyle(fontSize: 12, color: category.color),
            ),
          ],
        ),
      ),
    );
  }
}
