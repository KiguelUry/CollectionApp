import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/profile_cache_service.dart';
import '../services/profile_service.dart';
import '../services/showcase_service.dart';
import '../services/quick_log_service.dart';
import '../widgets/profile/quick_log_timeline.dart';
import 'friend_collection_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/preset_avatar_picker_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../utils/preset_avatars.dart';
import '../utils/app_page_route.dart';
import 'collection_share_screen.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _service = ProfileService();
  final _showcase = ShowcaseService();
  final _quickLog = QuickLogService();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();

  UserProfile? _profile;
  String _accentColor = profileAccentPresets.first;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  List<QuickLogEntry> _quickLogs = [];

  @override
  void initState() {
    super.initState();
    _accentColor = ProfileCacheService.instance.profile?.accentColor ??
        profileAccentPresets.first;
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
      final logs = await _quickLog.fetchMyLogs();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _usernameController.text = p.username;
        _bioController.text = p.bio ?? '';
        _accentColor = p.accentColor;
        _quickLogs = logs;
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
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo depuis la galerie'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.face_retouching_natural_outlined),
              title: const Text('Avatar'),
              onTap: () => Navigator.pop(ctx, 'preset'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'preset') {
      await _pickPresetAvatar();
      return;
    }

    setState(() => _uploadingAvatar = true);
    try {
      final url = await _service.pickAndUploadAvatar(cropContext: context);
      final updated = _profile!.copyWith(avatarUrl: url);
      final saved = await _service.updateProfileAndCache(updated);
      if (!mounted) return;
      setState(() => _profile = saved);
      await ProfileCacheService.instance.apply(saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo mise à jour')),
      );
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

  Future<void> _pickPresetAvatar() async {
    final asset = await showPresetAvatarPickerSheet(context);
    if (asset == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final saved = await _service.setPresetAvatar(asset);
      if (!mounted) return;
      setState(() => _profile = saved);
      await ProfileCacheService.instance.apply(saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar mis à jour')),
      );
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

  Future<void> _addQuickLog() async {
    final noteController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return AlertDialog(
          title: const Text('Quick Log'),
          content: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottom),
            child: TextField(
              controller: noteController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Qu\'as-tu fait ?',
                hintText: 'ex: Tome 1 de Kagurabachi lu ce soir',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final note = noteController.text.trim();
    if (note.isEmpty) return;
    try {
      await _quickLog.addLog(note: note);
      _quickLogs = await _quickLog.fetchMyLogs();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _deleteQuickLog(QuickLogEntry entry) async {
    try {
      await _quickLog.deleteLog(entry.id);
      _quickLogs = await _quickLog.fetchMyLogs();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_profile == null) return;

    setState(() => _saving = true);
    try {
      final username = _usernameController.text.trim();
      if (username.isEmpty) {
        throw Exception('Le pseudo ne peut pas être vide.');
      }
      final taken = await _service.isUsernameTaken(
        username,
        excludeUserId: _profile!.id,
      );
      if (taken) {
        throw Exception('Ce pseudo est déjà pris (même avec une autre casse).');
      }
      final updated = _profile!.copyWith(
        username: username,
        bio: _bioController.text,
        accentColor: _accentColor,
        clearBio: _bioController.text.trim().isEmpty,
      );
      final saved = await _service.updateProfileAndCache(updated);
      if (!mounted) return;
      setState(() => _profile = saved);
      await ProfileCacheService.instance.apply(saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil enregistré')),
      );
      Navigator.pop(context, true);
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
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent,
                Color.lerp(accent, Colors.white, 0.22) ?? accent,
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            tooltip: 'Enregistrer',
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
          ),
        ],
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
                          key: ValueKey(_profile?.avatarUrl ?? _accentColor),
                          avatarUrl: _profile?.avatarUrl,
                          accentColorHex: _accentColor,
                          fallbackInitial:
                              _profile?.username ?? _usernameController.text,
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
                      child: Text(
                        isPresetAvatarUrl(_profile?.avatarUrl)
                            ? 'Retirer l\'avatar'
                            : 'Supprimer la photo',
                      ),
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
                    decoration: InputDecoration(
                      labelText: 'Ta bio',
                      hintText: 'ex: Collectionneur de jeux familiaux',
                      border: const OutlineInputBorder(),
                      isDense: _bioController.text.trim().isEmpty,
                    ),
                    maxLength: 280,
                    maxLines: _bioController.text.trim().isEmpty ? 2 : 3,
                    minLines: 1,
                    onChanged: (_) => setState(() {}),
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
                  const SizedBox(height: 28),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.emoji_events_outlined, color: accent),
                    title: const Text('Mon Panthéon · Top 10'),
                    subtitle: const Text(
                      'Podium et collection sur ta page de profil',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final uid =
                          Supabase.instance.client.auth.currentUser?.id;
                      if (uid == null) return;
                      Navigator.push(
                        context,
                        appPageRoute(
                          builder: (_) => FriendCollectionScreen(
                            profileId: uid,
                            username: _profile?.username ??
                                _usernameController.text,
                            avatarUrl: _profile?.avatarUrl,
                            accentColor: _accentColor,
                            shareCollections: true,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.ios_share, color: accent),
                    title: const Text('Partage'),
                    subtitle: const Text(
                      'Exporter collection / wishlist (CSV ou page web)',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        appPageRoute(
                          builder: (_) => const CollectionShareScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  QuickLogTimeline(
                    entries: _quickLogs,
                    onAdd: _addQuickLog,
                    onDelete: _deleteQuickLog,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.public),
                          title: const Text('Vitrine publique'),
                          subtitle: Text(
                            _profile?.showcasePublic == true
                                ? 'Tes proches peuvent voir ta collection dans le navigateur'
                                : 'Lien web sans installer l\'app (collection + wishlist)',
                          ),
                          value: _profile?.showcasePublic ?? false,
                          onChanged: _saving
                              ? null
                              : (v) async {
                                  try {
                                    await _showcase.setPublic(v);
                                    await _load();
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          v
                                              ? 'Vitrine activée — partage le lien depuis le menu Partager'
                                              : 'Vitrine désactivée',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                },
                        ),
                        if (_profile?.showcasePublic == true &&
                            _profile?.showcaseToken != null)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.link, size: 20),
                            title: Text(
                              _showcase.buildUrl(_profile!.showcaseToken!),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                try {
                                  await _showcase.regenerateToken();
                                  await _load();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Nouveau lien généré (l\'ancien ne fonctionne plus)',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(content: Text('$e')),
                                  );
                                }
                              },
                              child: const Text('Renouveler'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
