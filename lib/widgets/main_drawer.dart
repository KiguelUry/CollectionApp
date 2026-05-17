import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../screens/login_screen.dart';
import '../screens/profile_edit_screen.dart';
import '../screens/inventory_manage_screen.dart';
import '../screens/loans_screen.dart';
import '../screens/shake_pick_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/wishlist_overview_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final accent = ProfileAvatar.colorFromHex(_profile?.accentColor);
    final username = _profile?.username ?? 'Ma collection';

    return Drawer(
      child: Column(
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
            accountEmail: Text(user?.email ?? 'Non connecté'),
            onDetailsPressed: _openProfile,
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Mon profil'),
            subtitle: const Text('Photo, couleur, bio'),
            onTap: _openProfile,
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Choisir une collection'),
            onTap: () => Navigator.pushReplacementNamed(context, '/categories'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Partager ma collection'),
            subtitle: const Text('Résumé pour amis sans l\'app, CSV'),
            onTap: () {
              Navigator.pop(context);
              showShareCollectionSheet(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('Statistiques'),
            subtitle: const Text('Graphiques et valorisation'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => const StatsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.shuffle),
            title: const Text('Shake to Pick'),
            subtitle: const Text('Tirage aléatoire dans ta collection'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => const ShakePickScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: const Text('Mes prêts'),
            subtitle: const Text('Objets prêtés à tes amis'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => const LoansScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_all),
            title: const Text('Doubles & ventes'),
            subtitle: const Text('À vendre, vendus, doublons'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => const InventoryManageScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Ma wishlist'),
            subtitle: const Text('Tous les objets à acquérir'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => const WishlistOverviewScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.groups),
            title: const Text('Groupes'),
            onTap: () => Navigator.pushNamed(context, '/groups'),
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Amis'),
            onTap: () => Navigator.pushNamed(context, '/friends'),
          ),
          const Divider(),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Déconnexion',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () async {
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
