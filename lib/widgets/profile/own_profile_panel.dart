import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/user_profile.dart';
import '../../utils/hub_greeting.dart';
import '../../services/profile_cache_service.dart';
import '../../services/profile_service.dart';
import '../../services/showcase_service.dart';
import '../preset_avatar_picker_sheet.dart';
import '../profile_avatar.dart';

/// Identité du compte (avatar, pseudo, bio, couleur, vitrine) sur la page profil.
class OwnProfilePanel extends StatefulWidget {
  static UserProfile? memory;

  const OwnProfilePanel({super.key});

  @override
  State<OwnProfilePanel> createState() => _OwnProfilePanelState();
}

class _OwnProfilePanelState extends State<OwnProfilePanel> {
  final _service = ProfileService();
  final _showcase = ShowcaseService();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  UserProfile? _profile = OwnProfilePanel.memory ?? ProfileCacheService.instance.profile;
  String _accent = profileAccentPresets.first;
  GrammarGender _grammar = GrammarGender.masculine;
  String _identity = 'Non précisé';
  bool _loading = OwnProfilePanel.memory == null &&
      ProfileCacheService.instance.profile == null;
  bool _saving = false;
  bool _uploading = false;
  String _visitorShow = 'all';
  Timer? _autosave;

  @override
  void initState() {
    super.initState();
    final known = _profile;
    if (known != null) {
      _username.text = known.username;
      _bio.text = known.bio ?? '';
      _accent = known.accentColor;
    }
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _service.fetchCurrentProfile();
      final localGrammar = await loadGrammarGender();
      final localIdentity = await loadGenderIdentity();
      final remote = await _service.fetchGreetingProfile();
      final identity = remote.identity ?? localIdentity ?? _identity;
      final grammar = switch (remote.grammar) {
        'feminine' => GrammarGender.feminine,
        'neutral' => GrammarGender.neutral,
        'masculine' => GrammarGender.masculine,
        _ => localGrammar,
      };
      if (remote.identity == null && identity.trim().isNotEmpty) {
        unawaited(
          _service.saveGreetingProfile(
            identity: identity,
            grammar: grammar.name,
          ),
        );
      }
      await saveGenderIdentity(identity);
      await saveGrammarGender(grammar);
      final prefs = await SharedPreferences.getInstance();
      final show = prefs.getString('showcase_visitor_show') ?? 'all';
      if (!mounted) return;
      OwnProfilePanel.memory = p;
      setState(() {
        _profile = p;
        _username.text = p.username;
        _bio.text = p.bio ?? '';
        _accent = p.accentColor;
        _grammar = grammar;
        _identity = identity;
        _visitorShow = show == 'owned' ? 'owned' : 'all';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _queueSave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _save);
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setVisitorShow(String show) async {
    setState(() => _visitorShow = show);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('showcase_visitor_show', show);
  }

  Future<void> _previewShowcase() async {
    final token = _profile?.showcaseToken;
    if (token == null || token.isEmpty) return;
    final uri = Uri.parse(_showcase.buildUrl(token, show: _visitorShow));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _persistGreeting() async {
    final identity = _identity.trim();
    if (identity.isEmpty) return;
    await saveGenderIdentity(identity);
    await saveGrammarGender(_grammar);
    await _service.saveGreetingProfile(
      identity: identity,
      grammar: _grammar.name,
    );
  }

  Future<void> _shareShowcase() async {
    try {
      final result = await _showcase.copyLink(show: _visitorShow);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final identity = <Widget>[
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
                      IconButton(
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
                          onChanged: (_) => _queueSave(),
                          decoration: const InputDecoration(
                            labelText: 'Pseudo',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _bio,
                          onChanged: (_) => _queueSave(),
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
                      onTap: () {
                        setState(() => _accent = hex);
                        _queueSave();
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: ProfileAvatar.colorFromHex(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: hex == _accent
                                ? Colors.black
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ];
            final preferences = <Widget>[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Genre',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: kGenderIdentities.contains(_identity)
                        ? _identity
                        : null,
                    items: [
                      for (final g in kGenderIdentities)
                        DropdownMenuItem(value: g, child: Text(g)),
                    ],
                    onChanged: (v) async {
                      if (v == null || v.trim().isEmpty) return;
                      setState(() => _identity = v);
                      await _persistGreeting();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Accord des salutations',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<GrammarGender>(
                    isExpanded: true,
                    value: _grammar,
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
                      await _persistGreeting();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.public, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Vitrine publique',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Switch(
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
                        ],
                      ),
                      if (_profile?.showcasePublic == true &&
                          _profile?.showcaseToken != null) ...[
                        const Text(
                          'Contenu visible via le lien',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ChoiceChip(
                              label: const Text('Collection + wishlist'),
                              selected: _visitorShow == 'all',
                              showCheckmark: false,
                              onSelected: (_) => _setVisitorShow('all'),
                            ),
                            ChoiceChip(
                              label: const Text('Collection seule'),
                              selected: _visitorShow == 'owned',
                              showCheckmark: false,
                              onSelected: (_) => _setVisitorShow('owned'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _previewShowcase,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Aperçu'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _shareShowcase,
                              icon: const Icon(Icons.link_rounded),
                              label: const Text('Copier le lien'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!wide) ...[
                  ...identity,
                  const SizedBox(height: 8),
                  ...preferences,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: identity,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: preferences,
                        ),
                      ),
                    ],
                  ),
                Divider(color: accent.withValues(alpha: 0.35)),
              ],
            );
          },
        ),
      ),
    );
  }
}
