import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_local_cache.dart';
import 'player_alias_service.dart';
import 'profile_cache_service.dart';

/// Suppression de compte : données Supabase puis déconnexion Auth.
class AccountDeletionService {
  final _client = Supabase.instance.client;

  Future<void> deleteAccount() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Non connecté');

    await _client.rpc('delete_my_account');
    await PlayerAliasService.instance.resetAllLocalData();
    await ProfileCacheService.instance.clear();
    await CollectionLocalCache.clearAll();
    await _client.auth.signOut();
  }
}
