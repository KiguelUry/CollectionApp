import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../widgets/app_app_bar.dart';
import 'category_manage_screen.dart';

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
