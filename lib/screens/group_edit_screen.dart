import 'package:flutter/material.dart';
import '../models/collection_group.dart';
import '../models/group_icon.dart';
import '../services/group_service.dart';
import '../widgets/group_badge.dart';
import '../widgets/profile_avatar.dart';

class GroupEditScreen extends StatefulWidget {
  final CollectionGroup group;

  const GroupEditScreen({super.key, required this.group});

  @override
  State<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _GroupEditScreenState extends State<GroupEditScreen> {
  final _service = GroupService();
  late final TextEditingController _nameController;

  late CollectionGroup _group;
  late String _accentColor;
  late String _iconKey;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;

  bool get _canEdit => _service.canEdit(_group);

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _accentColor = _group.accentColor;
    _iconKey = _group.iconKey;
    _nameController = TextEditingController(text: _group.name);
    _reload();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final g = await _service.fetchGroup(_group.id);
      if (!mounted) return;
      setState(() {
        _group = g;
        _accentColor = g.accentColor;
        _iconKey = g.iconKey;
        _nameController.text = g.name;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  Future<void> _changeAvatar() async {
    setState(() => _uploadingAvatar = true);
    try {
      final url = await _service.pickAndUploadGroupAvatar(_group.id);
      final saved = await _service.updateGroup(_group.copyWith(avatarUrl: url));
      if (mounted) {
        setState(() => _group = saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo du groupe mise à jour')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _uploadingAvatar = true);
    try {
      await _service.removeGroupAvatar(_group.id);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo supprimée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = _group.copyWith(
        name: _nameController.text,
        accentColor: _accentColor,
        iconKey: _iconKey,
      );
      final saved = await _service.updateGroup(updated);
      if (mounted) {
        Navigator.pop(context, saved);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(_accentColor);

    if (!_canEdit && !_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_group.name)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Seul le créateur du groupe peut modifier son apparence.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personnaliser le groupe'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        GroupBadge(
                          avatarUrl: _group.avatarUrl,
                          accentColorHex: _accentColor,
                          iconKey: _iconKey,
                          fallbackInitial: _group.name,
                          radius: 52,
                        ),
                        if (_uploadingAvatar)
                          Positioned.fill(
                            child: ColoredBox(
                              color: const Color(0x66000000),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        IconButton.filled(
                          onPressed:
                              _uploadingAvatar ? null : _changeAvatar,
                          icon: const Icon(Icons.camera_alt, size: 20),
                        ),
                      ],
                    ),
                  ),
                  if (_group.avatarUrl != null)
                    TextButton(
                      onPressed: _uploadingAvatar ? null : _removeAvatar,
                      child: const Text('Supprimer la photo'),
                    ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nom du groupe',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Icône',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: groupIconOptions.map((opt) {
                      final selected = opt.key == _iconKey;
                      final color = ProfileAvatar.colorFromHex(_accentColor);
                      return ChoiceChip(
                        label: Icon(opt.icon, size: 22, color: color),
                        selected: selected,
                        onSelected: (_) => setState(() => _iconKey = opt.key),
                        tooltip: opt.label,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Couleur',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: groupAccentPresets.map((hex) {
                      final color = ProfileAvatar.colorFromHex(hex);
                      final selected = hex == _accentColor;
                      return GestureDetector(
                        onTap: () => setState(() => _accentColor = hex),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.black
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
                  ),
                ],
              ),
            ),
    );
  }
}
