import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../widgets/profile_avatar.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _service = ProfileService();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();

  UserProfile? _profile;
  String _accentColor = profileAccentPresets.first;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _service.fetchCurrentProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _usernameController.text = p.username;
        _bioController.text = p.bio ?? '';
        _accentColor = p.accentColor;
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
      final url = await _service.pickAndUploadAvatar();
      final updated = _profile!.copyWith(avatarUrl: url);
      final saved = await _service.updateProfile(updated);
      if (mounted) {
        setState(() => _profile = saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo mise à jour')),
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
      await _service.removeAvatar();
      await _load();
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
    if (_profile == null) return;

    setState(() => _saving = true);
    try {
      final updated = _profile!.copyWith(
        username: _usernameController.text,
        bio: _bioController.text,
        accentColor: _accentColor,
        clearBio: _bioController.text.trim().isEmpty,
      );
      final saved = await _service.updateProfile(updated);
      if (mounted) {
        setState(() => _profile = saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil enregistré')),
        );
        Navigator.pop(context, true);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon profil'),
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
                        ProfileAvatar(
                          avatarUrl: _profile?.avatarUrl,
                          accentColorHex: _accentColor,
                          fallbackInitial: _profile?.username ?? '?',
                          radius: 52,
                        ),
                        if (_uploadingAvatar)
                          const Positioned.fill(
                            child: ColoredBox(
                              color: Color(0x66000000),
                              child: Center(
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
                  if (_profile?.avatarUrl != null)
                    TextButton(
                      onPressed: _uploadingAvatar ? null : _removeAvatar,
                      child: const Text('Supprimer la photo'),
                    ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Pseudo',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _bioController,
                    decoration: const InputDecoration(
                      labelText: 'Bio (optionnel)',
                      hintText: 'ex: Collectionneur de jeux familiaux',
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 280,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Couleur du profil',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: profileAccentPresets.map((hex) {
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
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
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
