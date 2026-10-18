import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/login_screen.dart';
import '../screens/friend_collection_screen.dart';
import '../screens/all_collection_screen.dart';
import '../screens/exchanges_screen.dart';
import '../screens/stats_screen.dart';
import '../services/auth_service.dart';
import '../services/profile_cache_service.dart';
import 'profile_avatar.dart';
import 'share_collection_sheet.dart';

class MainDrawer extends StatefulWidget {
  const MainDrawer({super.key});

  @override
  State<MainDrawer> createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  final _cache = ProfileCacheService.instance;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_onCacheChanged);
    if (_cache.profile == null) {
      _cache.refresh();
    }
  }

  @override
  void dispose() {
    _cache.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openProfile() async {
    final profile = _cache.profile;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    Navigator.pop(context);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FriendCollectionScreen(
          profileId: uid,
          username: profile?.username ?? 'Moi',
          avatarUrl: profile?.avatarUrl,
          accentColor: profile?.accentColor,
          shareCollections: true,
        ),
      ),
    );
    await _cache.refresh();
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, size: 22),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _cache.profile;
    final accent = ProfileAvatar.colorFromHex(
      profile?.accentColor,
      fallback: Colors.grey.shade700,
    );
    final username = profile?.username ?? 'Ma collection';
    final itemCount = _cache.itemCount;
    final showPlaceholder = profile == null && !_cache.hydrated;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openProfile,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent,
                              accent.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                        child: Column(
                          children: [
                            if (showPlaceholder)
                              const CircleAvatar(
                                radius: 40,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              ProfileAvatar(
                                key: ValueKey(profile?.avatarUrl ?? username),
                                avatarUrl: profile?.avatarUrl,
                                accentColorHex: profile?.accentColor,
                                fallbackInitial: username,
                                radius: 40,
                              ),
                            const SizedBox(height: 14),
                            Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '🚀 $itemCount objet${itemCount > 1 ? 's' : ''} collectionné${itemCount > 1 ? 's' : ''}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _item(
                    icon: Icons.all_inbox_rounded,
                    label: 'Toute ma collection',
                    onTap: () => _closeAndPush(const AllCollectionScreen()),
                  ),
                  _item(
                    icon: Icons.bar_chart_rounded,
                    label: 'Statistiques',
                    onTap: () => _closeAndPush(const StatsScreen()),
                  ),
                  _item(
                    icon: Icons.ios_share_rounded,
                    label: 'Partager',
                    onTap: () {
                      Navigator.pop(context);
                      showShareCollectionSheet(context);
                    },
                  ),
                  _item(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Échanges & Doublons',
                    onTap: () => _closeAndPush(const ExchangesScreen()),
                  ),
                  const Divider(height: 20),
                  _item(
                    icon: Icons.people_rounded,
                    label: 'Amis',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/friends');
                    },
                  ),
                  _item(
                    icon: Icons.groups_rounded,
                    label: 'Groupes',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/groups');
                    },
                  ),
                  _item(
                    icon: Icons.settings_rounded,
                    label: 'Paramètres',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
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
