import 'package:flutter/material.dart';
import '../utils/search_relevance.dart';

/// Choisir un ami dans une liste avec filtre en direct (tri par pertinence).
Future<String?> showFriendPickerDialog({
  required BuildContext context,
  required List<Map<String, dynamic>> friends,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _FriendPickerDialog(friends: friends),
  );
}

class _FriendPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> friends;

  const _FriendPickerDialog({required this.friends});

  @override
  State<_FriendPickerDialog> createState() => _FriendPickerDialogState();
}

class _FriendPickerDialogState extends State<_FriendPickerDialog> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.friends);
    _controller.addListener(_filter);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _controller.text.trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(widget.friends);
      } else {
        _filtered = widget.friends
            .where(
              (f) =>
                  titleRelevanceScore(f['username'] as String, q) > 0,
            )
            .toList();
        sortByScore(
          _filtered,
          (f) => titleRelevanceScore(f['username'] as String, q),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un membre'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Filtrer par pseudo…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('Aucun ami correspondant'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final f = _filtered[index];
                        return ListTile(
                          title: Text(f['username'] as String),
                          onTap: () => Navigator.pop(
                            context,
                            f['profile_id'] as String,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
