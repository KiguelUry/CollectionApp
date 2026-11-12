import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/rating_colors.dart';
import '../services/account_deletion_service.dart';
import '../services/auth_service.dart';
import '../services/account_export_service.dart';
import '../services/oauth_link_notice.dart';
import '../services/settings_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Paramètres'),
      body: ListView(
        children: [
          const _SectionHeader('Collections'),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Foyers & lieux liés'),
            onTap: () => showHouseholdsSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Gérer les catégories'),
            subtitle: const Text('Masquer ou supprimer des collections du hub'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CategoryManageScreen(),
              ),
            ),
          ),
          const BggCollectionImportCard(),
          const _SectionHeader('Apparence'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          const _SectionHeader('Notes sur les tuiles'),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: RatingColors.personal),
            title: const Text('Affichage de la note'),
            subtitle: Text(_settings.tileRatingDisplayMode.subtitle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                for (final mode in TileRatingDisplayMode.values)
                  RadioListTile<TileRatingDisplayMode>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(mode.label),
                    subtitle: Text(
                      mode.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    value: mode,
                    groupValue: _settings.tileRatingDisplayMode,
                    activeColor: mode == TileRatingDisplayMode.alwaysCommunity
                        ? RatingColors.community
                        : RatingColors.personal,
                    onChanged: (v) {
                      if (v != null) _settings.setTileRatingDisplayMode(v);
                    },
                  ),
              ],
            ),
          ),
          const _SectionHeader('Notifications'),
          SwitchListTile(
            title: const Text('Notifications'),
            value: _settings.notificationsEnabled,
            onChanged: (v) => _settings.setNotificationsEnabled(v),
          ),
          const _SectionHeader('Confidentialité'),
          SwitchListTile(
            title: const Text('Masquer ma collection aux non-amis'),
            subtitle: const Text(
              'Recommandé : seuls tes amis peuvent voir ta collection',
            ),
            value: _settings.hideCollectionFromNonFriends,
            onChanged: (v) => _settings.setHideFromNonFriends(v),
          ),
          SwitchListTile(
            title: const Text('Masquer ma collection à mes amis'),
            subtitle: const Text(
              'Désactivé par défaut : tes amis voient ta collection',
            ),
            value: _settings.hideCollectionFromFriends,
            onChanged: (v) => _settings.setHideFromFriends(v),
          ),
          SwitchListTile(
            title: const Text('Wishlist visible par mes amis'),
            subtitle: const Text(
              'Activé par défaut : tes amis peuvent voir ta wishlist',
            ),
            value: _settings.shareWishlistWithFriends,
            onChanged: (v) => _settings.setShareWishlistWithFriends(v),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('Qui voit quoi ?'),
            subtitle: const Text('Amis, groupes et données partagées'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PrivacyVisibilityScreen(),
              ),
            ),
          ),
          const _SectionHeader('Données & compte'),
          const _SectionHeader('Connexion Google et Discord'),
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
            leading: const Icon(Icons.alternate_email),
            title: const Text('Changer mon adresse e-mail'),
            subtitle: Text(
              Supabase.instance.client.auth.currentUser?.email ?? '',
            ),
            onTap: _changeEmail,
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Changer mon mot de passe'),
            onTap: _changePassword,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Exporter mes données (JSON)'),
            subtitle: const Text(
              'Collections, wishlists, parties, identités joueurs',
            ),
            onTap: _exportJson,
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: Text(
              'Supprimer mon compte',
              style: TextStyle(color: Colors.red.shade700),
            ),
            subtitle: const Text('Double confirmation — effacement définitif'),
            onTap: _confirmDeleteAccount,
          ),
        ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }
}
