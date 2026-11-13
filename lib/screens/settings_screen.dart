import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/rating_colors.dart';
import '../services/account_deletion_service.dart';
import '../services/auth_service.dart';
import '../services/account_export_service.dart';
import '../services/bgg_collection_import_service.dart';
import '../services/oauth_link_notice.dart';
import '../services/settings_service.dart';
import '../theme/card_skins.dart';
import '../utils/network_feedback.dart';
import '../utils/supabase_error_messages.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/bgg_collection_import_card.dart';
import '../widgets/households_sheet.dart';
import 'category_manage_screen.dart';
import 'privacy_visibility_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;

  @override
  void initState() {
    super.initState();
    _settings.load();
    _settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  Future<void> _linkProvider(OAuthProvider provider) async {
    final name = provider == OAuthProvider.discord ? 'discord' : 'google';
    final label = provider == OAuthProvider.discord ? 'Discord' : 'Google';
    await OAuthLinkNotice.remember(name);
    try {
      await AuthService().linkProvider(provider);
      if (!mounted) return;
      await OAuthLinkNotice.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compte $label associé avec succès !')),
      );
      setState(() {});
    } catch (e) {
      await OAuthLinkNotice.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeSupabaseError(e))),
      );
    }
  }

  Future<void> _unlinkProvider(String provider) async {
    final label = provider == 'discord' ? 'Discord' : 'Google';
    final auth = AuthService();
    if (auth.identityFor(provider) == null) return;
    final identities =
        Supabase.instance.client.auth.currentUser?.identities ?? const [];
    final hasOther = identities.any((item) => item.provider != provider);
    if (!hasOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible : c’est ton dernier moyen de connexion.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dissocier $label ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dissocier'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await auth.unlinkProvider(provider);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compte $label dissocié.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeSupabaseError(e))),
      );
    }
  }

  Future<void> _changeEmail() async {
    final auth = AuthService();
    final currentEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';
    final emailCtrl = TextEditingController(text: currentEmail);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer mon adresse e-mail'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nouvelle adresse'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty || email == currentEmail) {
                Navigator.pop(ctx);
                return;
              }
              try {
                await auth.updateEmail(email);
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Un e-mail de confirmation vient d’être envoyé à ta nouvelle adresse.',
                    ),
                  ),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(humanizeSupabaseError(e))),
                );
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    emailCtrl.dispose();
  }

  Future<void> _changePassword() async {
    final auth = AuthService();
    final passwordCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer mon mot de passe'),
        content: TextField(
          controller: passwordCtrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nouveau mot de passe',
            helperText: '6 caractères minimum.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await auth.updatePassword(passwordCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Le mot de passe a été mis à jour.'),
                  ),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(humanizeSupabaseError(e))),
                );
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    passwordCtrl.dispose();
  }

  Future<void> _exportJson() async {
    try {
      final json = await AccountExportService().exportAsJsonString();
      if (!mounted) return;
      await Share.share(json, subject: 'Export Paloma');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export JSON prêt à enregistrer ou partager')),
      );
    } catch (e) {
      if (mounted) showNetworkErrorSnackBar(context, e, prefix: 'Export');
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final ok1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text(
          'Toutes tes collections, parties et amitiés seront effacées '
          'définitivement sur nos serveurs. Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (ok1 != true || !mounted) return;

    final confirmCtrl = TextEditingController();
    final ok2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmation finale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tape SUPPRIMER pour confirmer.'),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              decoration: const InputDecoration(
                labelText: 'SUPPRIMER',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () =>
                Navigator.pop(ctx, confirmCtrl.text.trim() == 'SUPPRIMER'),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
    confirmCtrl.dispose();
    if (ok2 != true || !mounted) return;

    try {
      await AccountDeletionService().deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (e) {
      if (mounted) showNetworkErrorSnackBar(context, e, prefix: 'Suppression');
    }
  }

  Future<void> _signOut() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _openBggImport() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importer BoardGameGeek'),
        content: const SizedBox(
          width: 420,
          child: BggCollectionImportCard(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: const AppAppBar(title: 'Paramètres'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SettingsCard(
            title: 'Compte & Sécurité',
            children: [
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: const Text('Changer mon adresse e-mail'),
                subtitle: email.isEmpty ? null : Text(email),
                onTap: _changeEmail,
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Changer mon mot de passe'),
                onTap: _changePassword,
              ),
              _LinkedProviderTile(
                label: 'Google',
                linked: AuthService().providerLinked('google'),
                onLink: () => _linkProvider(OAuthProvider.google),
                onUnlink: () => _unlinkProvider('google'),
              ),
              _LinkedProviderTile(
                label: 'Discord',
                linked: AuthService().providerLinked('discord'),
                onLink: () => _linkProvider(OAuthProvider.discord),
                onUnlink: () => _unlinkProvider('discord'),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Déconnexion'),
                onTap: _signOut,
              ),
              ListTile(
                leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
                title: Text(
                  'Supprimer mon compte',
                  style: TextStyle(color: Colors.red.shade700),
                ),
                onTap: _confirmDeleteAccount,
              ),
            ],
          ),
          _SettingsCard(
            title: 'Apparence & Interface',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SegmentedButton<AppThemePreference>(
                  segments: const [
                    ButtonSegment(
                      value: AppThemePreference.system,
                      label: Text('Auto'),
                      icon: Icon(Icons.brightness_auto, size: 18),
                    ),
                    ButtonSegment(
                      value: AppThemePreference.light,
                      label: Text('Clair'),
                      icon: Icon(Icons.light_mode, size: 18),
                    ),
                    ButtonSegment(
                      value: AppThemePreference.dark,
                      label: Text('Sombre'),
                      icon: Icon(Icons.dark_mode, size: 18),
                    ),
                  ],
                  selected: {_settings.themePreference},
                  onSelectionChanged: (selection) {
                    _settings.setThemePreference(selection.first);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text('Fond de l\'application'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final choice in backgroundChoices)
                      ChoiceChip(
                        label: Text(choice.$1),
                        selected: _settings.scaffoldBackground.toARGB32() ==
                            choice.$2.toARGB32(),
                        onSelected: (_) =>
                            _settings.setScaffoldBackground(choice.$2),
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text('Styles de cartes'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _CardSkinGallery(
                  selectedId: _settings.cardSkin.id,
                  onSelected: _settings.setCardSkin,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.star_rounded, color: RatingColors.personal),
                title: const Text('Affichage de la note'),
                subtitle: Text(_settings.tileRatingDisplayMode.label),
              ),
              for (final mode in TileRatingDisplayMode.values)
                RadioListTile<TileRatingDisplayMode>(
                  dense: true,
                  title: Text(mode.label),
                  value: mode,
                  groupValue: _settings.tileRatingDisplayMode,
                  activeColor: mode == TileRatingDisplayMode.alwaysCommunity
                      ? RatingColors.community
                      : RatingColors.personal,
                  onChanged: (v) {
                    if (v != null) _settings.setTileRatingDisplayMode(v);
                  },
                ),
              SwitchListTile(
                title: const Text('Notifications'),
                value: _settings.notificationsEnabled,
                onChanged: (v) => _settings.setNotificationsEnabled(v),
              ),
            ],
          ),
          _SettingsCard(
            title: 'Collections & Imports',
            children: [
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Gérer les catégories'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CategoryManageScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Foyers & lieux liés'),
                onTap: () => showHouseholdsSheet(context),
              ),
              ValueListenableBuilder<BggImportProgress>(
                valueListenable: BggCollectionImportService.instance.progress,
                builder: (context, progress, _) {
                  return ListTile(
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: const Text('Importer ma collection BoardGameGeek'),
                    subtitle: progress.phase == BggImportPhase.idle
                        ? null
                        : Text(progress.message ?? 'Import en cours'),
                    onTap: _openBggImport,
                  );
                },
              ),
            ],
          ),
          _SettingsCard(
            title: 'Confidentialité & Données',
            children: [
              SwitchListTile(
                title: const Text('Masquer ma collection aux non-amis'),
                value: _settings.hideCollectionFromNonFriends,
                onChanged: (v) => _settings.setHideFromNonFriends(v),
              ),
              SwitchListTile(
                title: const Text('Masquer ma collection à mes amis'),
                value: _settings.hideCollectionFromFriends,
                onChanged: (v) => _settings.setHideFromFriends(v),
              ),
              SwitchListTile(
                title: const Text('Wishlist visible par mes amis'),
                value: _settings.shareWishlistWithFriends,
                onChanged: (v) => _settings.setShareWishlistWithFriends(v),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Qui voit quoi ?'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrivacyVisibilityScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Exporter mes données (JSON)'),
                onTap: _exportJson,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LinkedProviderTile extends StatelessWidget {
  const _LinkedProviderTile({
    required this.label,
    required this.linked,
    required this.onLink,
    required this.onUnlink,
  });

  final String label;
  final bool linked;
  final VoidCallback onLink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return ListTile(
      leading: Icon(linked ? Icons.check_circle : Icons.link),
      title: Text(
        linked ? '$label · Associé ✓' : 'Associer mon compte $label',
      ),
      trailing: linked
          ? TextButton(
              style: TextButton.styleFrom(foregroundColor: ink),
              onPressed: onUnlink,
              child: const Text('Dissocier'),
            )
          : null,
      onTap: linked ? null : onLink,
    );
  }
}

class _CardSkinGallery extends StatelessWidget {
  final String selectedId;
  final ValueChanged<CardSkin> onSelected;

  const _CardSkinGallery({
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final family in CardSkinFamily.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              switch (family) {
                CardSkinFamily.solid => 'Couleurs unies',
                CardSkinFamily.gradient => 'Dégradés',
                CardSkinFamily.special => 'Modes spéciaux',
              },
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skin in CardSkin.all)
                if (skin.family == family)
                  InkWell(
                    onTap: () => onSelected(skin),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 108,
                      padding: const EdgeInsets.all(8),
                      decoration: skin.decoration().copyWith(
                        border: Border.all(
                          color: skin.id == selectedId
                              ? Colors.white
                              : skin.edge,
                          width: skin.id == selectedId ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        skin.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}
