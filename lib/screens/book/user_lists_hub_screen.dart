import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/user_list.dart';
import '../../services/user_list_service.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/collection_cover_image.dart';
import 'user_list_detail_screen.dart';

class UserListsHubScreen extends StatefulWidget {
  const UserListsHubScreen({super.key});

  @override
  State<UserListsHubScreen> createState() => _UserListsHubScreenState();
}

class _UserListsHubScreenState extends State<UserListsHubScreen> {
  final _service = UserListService();
  bool _loading = true;
  List<UserListWithItems> _lists = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final lists = await _service.fetchAllWithPreviewItems();
      if (mounted) {
        setState(() {
          _lists = lists;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _createList() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle liste'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom',
                hintText: 'Mes lectures de l\'été',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
              ),
              maxLines: 2,
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
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    await _service.create(
      name: name,
      description: descController.text.trim().isEmpty
          ? null
          : descController.text.trim(),
    );
    _load();
  }

  Color _parseColor(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) {
      return Color(int.parse('FF$h', radix: 16));
    }
    return BookAccent.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: 'Mes listes',
        backgroundColor: BookAccent.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createList,
        backgroundColor: BookAccent.primary,
        icon: const Icon(Icons.add),
        label: const Text('Liste'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: BookAccent.primary,
              child: _lists.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Crée ta première liste thématique.\n'
                              'Ex. « Top 5 mangas », « Lectures été »…',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: _lists.length,
                      itemBuilder: (context, index) {
                        final bundle = _lists[index];
                        return _ListPosterCard(
                          bundle: bundle,
                          accent: _parseColor(bundle.list.colorHex),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => UserListDetailScreen(
                                  listId: bundle.list.id,
                                ),
                              ),
                            );
                            _load();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}

class _ListPosterCard extends StatelessWidget {
  final UserListWithItems bundle;
  final Color accent;
  final VoidCallback onTap;

  const _ListPosterCard({
    required this.bundle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final covers = bundle.previewCoverUrls;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.85),
                      accent.withValues(alpha: 0.45),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: covers.isEmpty
                      ? Center(
                          child: Icon(
                            Icons.playlist_play_rounded,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        )
                      : _CoverCollage(covers: covers),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              bundle.list.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            Text(
              '${bundle.itemCount} élément(s)',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverCollage extends StatelessWidget {
  final List<String> covers;

  const _CoverCollage({required this.covers});

  @override
  Widget build(BuildContext context) {
    if (covers.length == 1) {
      return CollectionCoverImage(
        url: covers.first,
        width: double.infinity,
        height: double.infinity,
        bookCover: true,
        fit: BoxFit.cover,
      );
    }
    return Row(
      children: [
        for (var i = 0; i < covers.length && i < 3; i++)
          Expanded(
            child: CollectionCoverImage(
              url: covers[i],
              width: double.infinity,
              height: double.infinity,
              bookCover: true,
              fit: BoxFit.cover,
            ),
          ),
      ],
    );
  }
}
