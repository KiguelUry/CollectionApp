import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/account_deletion_service.dart';
import '../services/account_export_service.dart';
import '../services/settings_service.dart';
import '../utils/network_feedback.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/bgg_collection_import_card.dart';
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

  Future<void> _exportJson() async {
    try {
      final json = await AccountExportService().exportAsJsonString();
      if (!mounted) return;
      await Share.share(json, subject: 'Export Collectingo');
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
          const _SectionHeader('Notifications'),
          SwitchListTile(
            title: const Text('Notifications'),
            subtitle: const Text(
              'Préférences enregistrées localement (push à venir)',
            ),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Ces réglages sont enregistrés sur ton profil Supabase et '
              'appliqués par la base de données.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
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
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
