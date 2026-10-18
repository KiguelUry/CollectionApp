import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../utils/hub_greeting.dart';
import '../../services/profile_cache_service.dart';
import '../../services/profile_service.dart';
import '../../services/showcase_service.dart';
import '../preset_avatar_picker_sheet.dart';
import '../profile_avatar.dart';

/// Identité du compte (avatar, pseudo, bio, couleur, vitrine) sur la page profil.
class OwnProfilePanel extends StatefulWidget {
  const OwnProfilePanel({super.key});

  @override
  State<OwnProfilePanel> createState() => _OwnProfilePanelState();
}

class _OwnProfilePanelState extends State<OwnProfilePanel> {
  final _service = ProfileService();
  final _showcase = ShowcaseService();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  UserProfile? _profile;
  String _accent = profileAccentPresets.first;
  GrammarGender _grammar = GrammarGender.masculine;
  String _identity = 'Non précisé';
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _service.fetchCurrentProfile();
      final grammar = await loadGrammarGender();
      final identity = await loadGenderIdentity();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _username.text = p.username;
        _bio.text = p.bio ?? '';
        _accent = p.accentColor;
        _grammar = grammar;
        _identity = identity ?? 'Non précisé';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_profile == null || _saving) return;
    setState(() => _saving = true);
    try {
      final username = _username.text.trim();
      if (username.isEmpty) {
        throw Exception('Le pseudo ne peut pas être vide.');
      }
      final taken = await _service.isUsernameTaken(
        username,
        excludeUserId: _profile!.id,
      );
      if (taken) throw Exception('Ce pseudo est déjà pris.');
      final saved = await _service.updateProfileAndCache(
        _profile!.copyWith(
          username: username,
          bio: _bio.text,
          accentColor: _accent,
          clearBio: _bio.text.trim().isEmpty,
        ),
      );
      await ProfileCacheService.instance.apply(saved);
      if (!mounted) return;
      setState(() => _profile = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil enregistré')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
    if (choice == null || !mounted || _profile == null) return;
    setState(() => _uploading = true);
    try {
      final UserProfile saved;
      if (choice == 'preset') {
        final asset = await showPresetAvatarPickerSheet(context);
        if (asset == null || !mounted) return;
        saved = await _service.setPresetAvatar(asset);
      } else {
        final url = await _service.pickAndUploadAvatar(cropContext: context);
        saved = await _service.updateProfileAndCache(
          _profile!.copyWith(avatarUrl: url),
        );
      }
      await ProfileCacheService.instance.apply(saved);
      if (mounted) setState(() => _profile = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final accent = ProfileAvatar.colorFromHex(_accent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                ProfileAvatar(
                  avatarUrl: _profile?.avatarUrl,
                  accentColorHex: _accent,
                  fallbackInitial: _username.text,
                  radius: 36,
                ),
                if (_uploading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                IconButton.filled(
                  visualDensity: VisualDensity.compact,
                  onPressed: _uploading ? null : _changeAvatar,
                  icon: const Icon(Icons.camera_alt, size: 16),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Pseudo',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bio,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 280,
                    minLines: 1,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in profileAccentPresets)
              GestureDetector(
                onTap: () => setState(() => _accent = hex),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: ProfileAvatar.colorFromHex(hex),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hex == _accent ? Colors.black : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: kGenderIdentities.contains(_identity) ? _identity : null,
          decoration: const InputDecoration(
            labelText: 'Genre',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final g in kGenderIdentities)
              DropdownMenuItem(value: g, child: Text(g)),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _identity = v);
            await saveGenderIdentity(v);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<GrammarGender>(
          initialValue: _grammar,
          decoration: const InputDecoration(
            labelText: 'Accord des salutations',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: GrammarGender.feminine,
              child: Text('Féminin (Aventurière…)'),
            ),
            DropdownMenuItem(
              value: GrammarGender.masculine,
              child: Text('Masculin (Aventurier…)'),
            ),
            DropdownMenuItem(
              value: GrammarGender.neutral,
              child: Text('Aucun — seulement le pseudo'),
            ),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _grammar = v);
            await saveGrammarGender(v);
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.public),
          title: const Text('Vitrine publique'),
          subtitle: const Text('Lien web de ta collection'),
          value: _profile?.showcasePublic ?? false,
          onChanged: (v) async {
            try {
              await _showcase.setPublic(v);
              await _load();
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$e')),
              );
            }
          },
        ),
        if (_profile?.showcasePublic == true && _profile?.showcaseToken != null)
          Text(
            _showcase.buildUrl(_profile!.showcaseToken!),
            style: const TextStyle(fontSize: 12),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Enregistrer'),
          ),
        ),
        Divider(color: accent.withValues(alpha: 0.35)),
      ],
    );
  }
}
