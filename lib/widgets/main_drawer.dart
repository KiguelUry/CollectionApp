import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../screens/login_screen.dart';
import '../screens/profile_edit_screen.dart';
import '../screens/inventory_manage_screen.dart';
import '../screens/loans_screen.dart';
import '../screens/stats_screen.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import 'profile_avatar.dart';
import 'share_collection_sheet.dart';

class MainDrawer extends StatefulWidget {
  const MainDrawer({super.key});

  @override
  State<MainDrawer> createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  UserProfile? _profile;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await ProfileService().fetchCurrentProfile();
      if (mounted) {
        setState(() {
          _profile = p;
          _loadingProfile = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _openProfile() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
    );
    if (changed == true) _loadProfile();
  }

  void _closeAndPush(Widget screen) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 22),
      title: Text(label),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final accent = ProfileAvatar.colorFromHex(_profile?.accentColor);
    final username = _profile?.username ?? 'Ma collection';

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  UserAccountsDrawerHeader(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0.75)],
                      ),
                    ),
                    currentAccountPicture: _loadingProfile
                        ? const CircleAvatar(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : ProfileAvatar(
                            avatarUrl: _profile?.avatarUrl,
                            accentColorHex: _profile?.accentColor,
                            fallbackInitial: username,
                            radius: 36,
                          ),
                    accountName: Text(
                      username,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    accountEmail: Text(
                      user?.email ?? 'Non connecté',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDetailsPressed: _openProfile,
                  ),
                  _item(
                    icon: Icons.grid_view_outlined,
                    label: 'Collections',
                    onTap: () =>
                        Navigator.pushReplacementNamed(context, '/categories'),
                  ),
                  _item(
                    icon: Icons.bar_chart_outlined,
                    label: 'Statistiques',
                    onTap: () => _closeAndPush(const StatsScreen()),
                  ),
                  _item(
                    icon: Icons.ios_share,
                    label: 'Partager',
                    onTap: () {
                      Navigator.pop(context);
                      showShareCollectionSheet(context);
                    },
                  ),
                  _item(
                    icon: Icons.handshake_outlined,
                    label: 'Prêts',
                    onTap: () => _closeAndPush(const LoansScreen()),
                  ),
                  _item(
                    icon: Icons.copy_all_outlined,
                    label: 'Doubles & ventes',
                    onTap: () => _closeAndPush(const InventoryManageScreen()),
                  ),
                  const Divider(height: 1),
                  _item(
                    icon: Icons.people_outline,
                    label: 'Amis',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/friends');
                    },
                  ),
                  _item(
                    icon: Icons.groups_outlined,
                    label: 'Groupes',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/groups');
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.logout, color: Colors.red, size: 22),
              title: const Text(
                'Déconnexion',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                await AuthService().signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
