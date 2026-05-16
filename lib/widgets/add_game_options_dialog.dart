import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddGameOptionsDialog extends StatefulWidget {
  final String gameTitle;
  final Function(bool isWishlist, String? profileId) onConfirm;

  const AddGameOptionsDialog({
    super.key,
    required this.gameTitle,
    required this.onConfirm,
  });

  @override
  State<AddGameOptionsDialog> createState() => _AddGameOptionsDialogState();
}

class _AddGameOptionsDialogState extends State<AddGameOptionsDialog> {
  bool _isWishlist = false;
  String? _selectedProfileId;
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
  }

  Future<void> _fetchProfiles() async {
    final data = await Supabase.instance.client
        .from('profiles')
        .select('id, username');
    if (mounted) {
      setState(() {
        _profiles = List<Map<String, dynamic>>.from(data);
        if (_profiles.isNotEmpty) _selectedProfileId = _profiles.first['id'];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Ajouter ${widget.gameTitle}"),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text("Ajouter à la Wishlist"),
                  value: _isWishlist,
                  onChanged: (val) => setState(() => _isWishlist = val),
                ),
                if (!_isWishlist && _profiles.isNotEmpty)
                  DropdownButtonFormField<String>(
                    // CORRECTION : On utilise l'ID de l'utilisateur
                    value: _selectedProfileId,
                    decoration: const InputDecoration(
                      labelText: "Qui a le jeu ?",
                    ),
                    items: _profiles
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['id'].toString(),
                            child: Text(p['username']),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedProfileId = val),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Annuler"),
        ),
        ElevatedButton(
          onPressed: () => widget.onConfirm(_isWishlist, _selectedProfileId),
          child: const Text("Confirmer"),
        ),
      ],
    );
  }
}
