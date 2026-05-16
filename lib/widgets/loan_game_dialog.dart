import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoanGameDialog extends StatefulWidget {
  final String gameTitle;
  final Function(String? profileId, String? externalName) onConfirm;

  const LoanGameDialog({
    super.key,
    required this.gameTitle,
    required this.onConfirm,
  });

  @override
  State<LoanGameDialog> createState() => _LoanGameDialogState();
}

class _LoanGameDialogState extends State<LoanGameDialog> {
  String? _selectedProfileId;
  final _nameController = TextEditingController();
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;
  bool _isExternal = false; // Mode "Ami hors-app"

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
  }

  Future<void> _fetchProfiles() async {
    final data = await Supabase.instance.client
        .from('profiles')
        .select('id, username');
    setState(() {
      _profiles = List<Map<String, dynamic>>.from(data);
      if (_profiles.isNotEmpty) _selectedProfileId = _profiles.first['id'];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Prêter ${widget.gameTitle}"),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text("Prêter à quelqu'un hors-famille ?"),
                  value: _isExternal,
                  onChanged: (val) => setState(() => _isExternal = val!),
                ),
                if (_isExternal)
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: "Nom de l'ami (ex: Titouan)",
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue:
                        _selectedProfileId, // Correction du lint 'value' déprécié
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
                    decoration: const InputDecoration(
                      labelText: "Membre de la famille",
                    ),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Annuler"),
        ),
        ElevatedButton(
          onPressed: () => widget.onConfirm(
            _isExternal ? null : _selectedProfileId,
            _isExternal ? _nameController.text : null,
          ),
          child: const Text("Confirmer le prêt"),
        ),
      ],
    );
  }
}
