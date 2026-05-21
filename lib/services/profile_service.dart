import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../models/user_profile.dart';
import '../utils/collection_item_filters.dart';
import 'activity_service.dart';

class ProfileService {
  final _client = Supabase.instance.client;
  final _picker = ImagePicker();

  String? get _userId => _client.auth.currentUser?.id;

  /// Crée la ligne `profiles` si absente (comptes créés sans inscription app).
  Future<void> ensureCurrentUserProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final existing = await _client
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    if (existing != null) return;

    final username = _defaultUsername(user);
    try {
      await _client.from('profiles').insert({
        'id': user.id,
        'username': username,
      });
    } on PostgrestException catch (e) {
      // Ligne créée entre-temps (trigger SQL ou autre appareil)
      if (e.code == '23505') return;
      rethrow;
    }
  }

  /// Message lisible si l'insert collection_items échoue sur la FK profil.
  static bool isMissingProfileFk(PostgrestException e) {
    return e.code == '23503' &&
        (e.message.contains('collection_items_added_by_fkey') ||
            e.message.contains('collection_items_location_user_id_fkey') ||
            e.message.contains('profiles'));
  }

  static String missingProfileUserMessage() {
    return 'Ton compte n\'a pas encore de profil dans l\'app. '
        'Déconnecte-toi, reconnecte-toi, ou demande à l\'admin '
        'd\'exécuter le script SQL « profiles backfill » sur Supabase.';
  }

  static String _defaultUsername(User user) {
    final meta = user.userMetadata;
    final fromMeta = meta?['username'];
    if (fromMeta is String && fromMeta.trim().isNotEmpty) {
      return fromMeta.trim();
    }
    final email = user.email;
    if (email != null && email.contains('@')) {
      final local = email.split('@').first.trim();
      if (local.isNotEmpty) return local;
    }
    return 'user_${user.id.substring(0, 8)}';
  }

  static const _profileSelectFull =
      'id, username, bio, avatar_url, accent_color, showcase_public, '
      'showcase_token, share_wishlist, hide_collection_from_non_friends, '
      'hide_collection_from_friends, favorite_item_ids';

  static const _profileSelectLegacy =
      'id, username, bio, avatar_url, accent_color, showcase_public, '
      'showcase_token, share_wishlist';

  Future<Map<String, dynamic>> _fetchProfileRow(
    String profileId, {
    required String columns,
  }) async {
    final row =
        await _client.from('profiles').select(columns).eq('id', profileId).single();
    return Map<String, dynamic>.from(row);
  }

  Future<UserProfile> fetchCurrentProfile() async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');
    return UserProfile.fromJson(await _fetchProfileRowSafe(id));
  }

  Future<UserProfile> fetchProfile(String profileId) async {
    return UserProfile.fromJson(await _fetchProfileRowSafe(profileId));
  }

  Future<Map<String, dynamic>> _fetchProfileRowSafe(String profileId) async {
    try {
      return await _fetchProfileRow(profileId, columns: _profileSelectFull);
    } on PostgrestException catch (e) {
      if (!_isMissingColumnError(e)) rethrow;
      final row =
          await _fetchProfileRow(profileId, columns: _profileSelectLegacy);
      return {
        ...row,
        'hide_collection_from_non_friends': true,
        'hide_collection_from_friends': false,
        'favorite_item_ids': <String>[],
      };
    }
  }

  static bool _isMissingColumnError(PostgrestException e) {
    return e.code == '42703' ||
        e.message.contains('does not exist') ||
        e.message.contains('favorite_item_ids') ||
        e.message.contains('hide_collection');
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    final id = _userId;
    if (id == null || id != profile.id) {
      throw Exception('Modification non autorisée');
    }

    final row = await _client
        .from('profiles')
        .update(profile.toUpdateJson())
        .eq('id', id)
        .select()
        .single();

    return UserProfile.fromJson(Map<String, dynamic>.from(row));
  }

  /// Choisit une image (galerie) et l'envoie dans Storage `avatars/{userId}/avatar.jpg`.
  Future<String> pickAndUploadAvatar() async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) {
      throw Exception('Aucune image sélectionnée');
    }

    final bytes = await picked.readAsBytes();
    return uploadAvatarBytes(bytes);
  }

  Future<String> uploadAvatarBytes(Uint8List bytes) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final path = '$id/avatar.jpg';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final publicUrl = _client.storage.from('avatars').getPublicUrl(path);
    // Cache-bust pour forcer le rafraîchissement après remplacement
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> removeAvatar() async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    try {
      await _client.storage.from('avatars').remove(['$id/avatar.jpg']);
    } catch (_) {
      // Fichier peut ne pas exister
    }

    await _client
        .from('profiles')
        .update({'avatar_url': null})
        .eq('id', id);
  }

  Future<void> updateShareWishlist(bool share) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    await _client
        .from('profiles')
        .update({'share_wishlist': share})
        .eq('id', id);
  }

  Future<List<CollectionItem>> fetchFavoriteItems(List<String> itemIds) async {
    if (itemIds.isEmpty) return [];

    final rows = await _client
        .from('collection_items')
        .select('*, locations(label), groups(name)')
        .inFilter('id', itemIds);

    final byId = <String, CollectionItem>{};
    for (final row in rows as List) {
      final item = CollectionItem.fromJson(Map<String, dynamic>.from(row));
      if (isActiveCollectionItem(item)) byId[item.id] = item;
    }

    return [
      for (final id in itemIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Future<List<CollectionItem>> fetchPickableTrophyCandidates() async {
    final id = _userId;
    if (id == null) return [];

    final rows = await _client
        .from('collection_items')
        .select('*, locations(label), groups(name)')
        .or('added_by.eq.$id,location_user_id.eq.$id')
        .eq('is_wishlist', false)
        .order('title')
        .limit(120);

    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where(isActiveCollectionItem)
        .toList();
  }

  Future<UserProfile> updateFavoriteItemIds(List<String> ids) async {
    final userId = _userId;
    if (userId == null) throw Exception('Non connecté');
    if (ids.length > 6) {
      throw Exception('6 trophées maximum');
    }

    final row = await _client
        .from('profiles')
        .update({'favorite_item_ids': ids})
        .eq('id', userId)
        .select()
        .single();

    await ActivityService().logTrophiesUpdated();

    return UserProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> updateCollectionPrivacy({
    required bool hideFromNonFriends,
    required bool hideFromFriends,
  }) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    await _client.from('profiles').update({
      'hide_collection_from_non_friends': hideFromNonFriends,
      'hide_collection_from_friends': hideFromFriends,
    }).eq('id', id);
  }
}
