import 'package:flutter/material.dart';
import '../services/friend_service.dart';
import 'profile_avatar.dart';

/// Résultat d'un dialogue de prêt.
class LoanDialogResult {
  final String? profileId;
  final String? displayName;
  final String? externalName;

  const LoanDialogResult.friend({
    required this.profileId,
    required this.displayName,
  })  : externalName = null;

  const LoanDialogResult.external({required this.externalName})
      : profileId = null,
        displayName = null;
}

Future<LoanDialogResult?> showLoanItemDialog({
  required BuildContext context,
  required String itemTitle,
}) {
  return showDialog<LoanDialogResult>(
    context: context,
    builder: (ctx) => LoanItemDialog(itemTitle: itemTitle),
  );
}

class LoanItemDialog extends StatefulWidget {
  final String itemTitle;

  const LoanItemDialog({super.key, required this.itemTitle});

  @override
  State<LoanItemDialog> createState() => _LoanItemDialogState();
}

class _LoanItemDialogState extends State<LoanItemDialog> {
  final _friendService = FriendService();
  final _nameController = TextEditingController();

  List<Map<String, dynamic>> _friends = [];
  String? _selectedProfileId;
  bool _isExternal = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      _friends = await _friendService.fetchFriends();
      if (_friends.isNotEmpty) {
        _selectedProfileId = _friends.first['profile_id'] as String;
      }
    } catch (_) {
      _friends = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _confirm() {
    if (_isExternal) {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indique un nom')),
        );
        return;
      }
      Navigator.pop(
        context,
        LoanDialogResult.external(externalName: name),
      );
      return;
    }

    if (_selectedProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoute des amis dans le menu ou utilise « Hors app »'),
        ),
      );
      return;
    }

    final friend = _friends.firstWhere(
      (f) => f['profile_id'] == _selectedProfileId,
    );
    Navigator.pop(
      context,
      LoanDialogResult.friend(
        profileId: _selectedProfileId!,
        displayName: friend['username'] as String,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Prêter « ${widget.itemTitle} »'),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Ami'),
                        icon: Icon(Icons.people, size: 18),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Hors app'),
                        icon: Icon(Icons.person_outline, size: 18),
                      ),
                    ],
                    selected: {_isExternal},
                    onSelectionChanged: (s) =>
                        setState(() => _isExternal = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_isExternal)
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nom (ex: Titouan)',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    )
                  else if (_friends.isEmpty)
                    Text(
                      'Tu n\'as pas encore d\'amis sur l\'app. '
                      'Ajoute-en depuis le menu « Amis », ou prête à quelqu\'un hors app.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedProfileId,
                      decoration: const InputDecoration(
                        labelText: 'Choisir un ami',
                        border: OutlineInputBorder(),
                      ),
                      items: _friends
                          .map(
                            (f) => DropdownMenuItem(
                              value: f['profile_id'] as String,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ProfileAvatar(
                                    avatarUrl: f['avatar_url'] as String?,
                                    accentColorHex:
                                        f['accent_color'] as String?,
                                    fallbackInitial:
                                        f['username'] as String? ?? '?',
                                    radius: 16,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(f['username'] as String),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedProfileId = v),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _loading ? null : _confirm,
          child: const Text('Confirmer le prêt'),
        ),
      ],
    );
  }
}
