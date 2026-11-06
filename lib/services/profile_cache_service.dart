import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import '../utils/active_categories.dart';
import '../utils/hub_owned_count.dart';
import 'inventory_service.dart';
import 'profile_service.dart';

/// Cache profil (mémoire + disque) pour éviter le flash drawer au chargement.
class ProfileCacheService extends ChangeNotifier {
  ProfileCacheService._();
  static final ProfileCacheService instance = ProfileCacheService._();

  static const _kId = 'profile_cache_id';
  static const _kUsername = 'profile_cache_username';
  static const _kAccent = 'profile_cache_accent';
  static const _kAvatar = 'profile_cache_avatar_url';
  static const _kItemCount = 'profile_cache_item_count';

  UserProfile? profile;
  int itemCount = 0;
  bool hydrated = false;

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kId);
    final username = prefs.getString(_kUsername);
    if (id != null && username != null) {
      profile = UserProfile(
        id: id,
        username: username,
        accentColor: prefs.getString(_kAccent) ?? profileAccentPresets.first,
        avatarUrl: prefs.getString(_kAvatar),
      );
      itemCount = prefs.getInt(_kItemCount) ?? 0;
    }
    hydrated = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final p = await ProfileService().fetchCurrentProfile();
      final count = await _ownedCountLikeHub(userId);
      await apply(p, itemCount: count);
    } catch (_) {}
  }

  /// Même total que la carte « Toute ma collection » du hub.
  Future<int> _ownedCountLikeHub(String userId) async {
    final items = await InventoryService().fetchOwnedItems();
    final owned = [
      for (final i in items)
        if (!i.isWishlist && !i.isSold) i,
    ];
    final active = await ActiveCategories.load();
    return hubOwnedItems(owned, active: active).length;
  }

  Future<void> apply(UserProfile p, {int? itemCount}) async {
    profile = p;
    if (itemCount != null) this.itemCount = itemCount;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kId, p.id);
    await prefs.setString(_kUsername, p.username);
    await prefs.setString(_kAccent, p.accentColor);
    if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) {
      await prefs.setString(_kAvatar, p.avatarUrl!);
    } else {
      await prefs.remove(_kAvatar);
    }
    if (itemCount != null) {
      await prefs.setInt(_kItemCount, itemCount);
    }
  }

  Future<void> clear() async {
    profile = null;
    itemCount = 0;
    hydrated = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kId);
    await prefs.remove(_kUsername);
    await prefs.remove(_kAccent);
    await prefs.remove(_kAvatar);
    await prefs.remove(_kItemCount);
  }
}
