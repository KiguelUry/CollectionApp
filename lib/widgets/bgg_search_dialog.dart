import 'package:flutter/material.dart';
import '../services/bgg_service.dart';

class BggSearchDialog extends StatefulWidget {
  final Function(Map<String, String>) onGameSelected;

  const BggSearchDialog({super.key, required this.onGameSelected});

  @override
  State<BggSearchDialog> createState() => _BggSearchDialogState();
}

class _BggSearchDialogState extends State<BggSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, String>> _results = [];
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chercher sur BGG'),
      content: SizedBox(
        width: double.maxFinite,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "Titre du jeu...",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_controller.text),
                ),
              ),
              onSubmitted: _search,
            ),
            if (_isLoading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final game = _results[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.casino_outlined,
                    ), // L'icône par défaut
                    title: Text(game['title']!),
                    subtitle: Text(game['year']!),
                    onTap: () => widget.onGameSelected(game),
                  );
                },
              ),
            ),
            const Divider(),
            const Text(
              "Powered by BoardGameGeek",
              style: TextStyle(fontSize: 9, color: Colors.grey),
            ), // Obligatoire
          ],
        ),
      ),
    );
  }

  Future<void> _search(String query) async {
    if (query.length < 3) return;
    setState(() => _isLoading = true);
    final res = await BggService.searchGames(query);
    setState(() {
      _results = res;
      _isLoading = false;
    });
  }
}
