import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'image_compression_service.dart';

import '../widgets/avatar_crop_sheet.dart';
import '../models/collection_item.dart';
import '../models/user_profile.dart';
import '../utils/preset_avatars.dart';
import '../utils/picked_image_bytes.dart';
import '../utils/collection_item_filters.dart';
import '../utils/supabase_embeds.dart';
import 'activity_service.dart';
import 'profile_cache_service.dart';

class ProfileService {
  SupabaseClient get _client => Supabase.instance.client;
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

    final username = needsProfileSetup(user)
        ? 'user_${user.id.substring(0, 8)}'
        : _defaultUsername(user);
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

  /// Premier login Google / Discord tant que le surnom n'a pas été choisi.
  static bool needsProfileSetup(User? user) {
    if (user == null) return false;
    final meta = user.userMetadata;
    if (meta?['profile_ready'] == true) return false;
    final providers = <String>{
      for (final identity in user.identities ?? const [])
        identity.provider,
    };
    final oauth =
        providers.contains('google') || providers.contains('discord');
    if (!oauth) return false;
    if (providers.contains('email') && meta?['profile_ready'] != false) {
      return false;
    }
    return true;
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

  static const _profileSelectWide =
      '$_profileSelectFull, households, household_aliases, gender_identity, '
      'greeting_grammar, pantheon_item_ids';

  static const _profileTtl = Duration(minutes: 10);
  static final Map<String, ({DateTime at, Map<String, dynamic> row})>
      _profileRows = {};

  static void invalidateCachedProfile([String? profileId]) {
    if (profileId == null) {
      _profileRows.clear();
    } else {
      _profileRows.remove(profileId);
    }
  }

  /// Ligne profil (courant ou ami) gardée 10 minutes. `null` si le select large
  /// n'est pas encore en base : l'appelant retombe sur sa requête étroite.
  Future<Map<String, dynamic>?> cachedProfileRow(String profileId) async {
    final hit = _profileRows[profileId];
    if (hit != null && DateTime.now().difference(hit.at) < _profileTtl) {
      return hit.row;
    }
    try {
      final row = await _fetchProfileRow(profileId, columns: _profileSelectWide);
      _profileRows[profileId] = (at: DateTime.now(), row: row);
      return row;
    } on PostgrestException {
      return null;
    }
  }

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
    var profile = UserProfile.fromJson(await _fetchProfileRowSafe(id));
    profile = await _restoreUsernameIfEmailOverwrite(profile);
    await ProfileCacheService.instance.apply(profile);
    return profile;
  }

  /// Un changement de mail ou un lien Google/Discord ne doit pas remplacer
  /// le pseudo déjà choisi par le début de l'adresse.
  Future<UserProfile> _restoreUsernameIfEmailOverwrite(UserProfile profile) async {
    final email = _client.auth.currentUser?.email;
    final local = email?.split('@').first.trim().toLowerCase();
    if (local == null || local.isEmpty) return profile;
    if (profile.username.trim().toLowerCase() != local) return profile;
    final prefs = await SharedPreferences.getInstance();
    final cachedName = ProfileCacheService.instance.profile?.id == profile.id
        ? ProfileCacheService.instance.profile?.username
        : null;
    final chosen = prefs.getString('profile_username_chosen') ?? cachedName;
    if (chosen == null ||
        chosen.trim().isEmpty ||
        chosen.trim().toLowerCase() == local) {
      return profile;
    }
    invalidateCachedProfile(profile.id);
    final row = await _client
        .from('profiles')
        .update({'username': chosen.trim()})
        .eq('id', profile.id)
        .select()
        .single();
    return UserProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<UserProfile> fetchProfile(String profileId) async {
    return UserProfile.fromJson(await _fetchProfileRowSafe(profileId));
  }

  Future<Map<String, dynamic>> _fetchProfileRowSafe(String profileId) async {
    final cached = _profileRows[profileId];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _profileTtl &&
        cached.row.containsKey('username')) {
      return Map<String, dynamic>.from(cached.row);
    }
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

  Future<bool> isUsernameTaken(
    String username, {
    String? excludeUserId,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return true;

    final exact = trimmed
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await _client
        .from('profiles')
        .select('id')
        .ilike('username', exact);

    for (final row in rows as List) {
      final id = row['id'] as String?;
      if (id != null && id != excludeUserId) return true;
    }
    return false;
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    final id = _userId;
    if (id == null || id != profile.id) {
      throw Exception('Modification non autorisée');
    }

    final trimmedName = profile.username.trim();
    if (trimmedName.length > 18) {
      throw Exception('Le pseudo est limité à 18 caractères');
    }
    final row = await _client
        .from('profiles')
        .update(profile.toUpdateJson())
        .eq('id', id)
        .select()
        .single();

    final saved = UserProfile.fromJson(Map<String, dynamic>.from(row));
    final emailLocal =
        _client.auth.currentUser?.email?.split('@').first.trim().toLowerCase();
    if (emailLocal == null ||
        saved.username.trim().toLowerCase() != emailLocal) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_username_chosen', saved.username.trim());
    }
    return saved;
  }

  Future<UserProfile> updateProfileAndCache(UserProfile profile) async {
    final saved = await updateProfile(profile);
    await ProfileCacheService.instance.apply(saved);
    return saved;
  }

  /// Choisit une image (galerie), recadre et l'envoie dans Storage.
  Future<String> pickAndUploadAvatar({BuildContext? cropContext}) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
      requestFullMetadata: true,
    );
    if (picked == null) {
      throw Exception('Aucune image sélectionnée');
    }

    Uint8List bytes = await readPickedImageBytes(picked);
    if (cropContext != null && cropContext.mounted) {
      final cropped = await AvatarCropSheet.show(cropContext, bytes);
      if (cropped == null) {
        throw Exception('Recadrage annulé');
      }
      bytes = cropped;
    }
    return uploadAvatarBytes(bytes);
  }

  Future<String> uploadAvatarBytes(Uint8List bytes) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final compressed = await ImageCompressionService.compressForUpload(bytes);
    final path = '$id/avatar.jpg';
    await _client.storage.from('avatars').uploadBinary(
          path,
          compressed,
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

  Future<UserProfile> setPresetAvatar(String assetPath) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final url = presetAvatarUrl(assetPath);
    final row = await _client
        .from('profiles')
        .update({'avatar_url': url})
        .eq('id', id)
        .select()
        .single();
    return UserProfile.fromJson(Map<String, dynamic>.from(row));
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
        .select(SupabaseEmbeds.collectionItem)
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
        .select(SupabaseEmbeds.collectionItem)
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
    if (ids.length > 100) {
      throw Exception('100 objets maximum dans la vitrine');
    }

    invalidateCachedProfile(userId);
    final row = await _client
        .from('profiles')
        .update({'favorite_item_ids': ids})
        .eq('id', userId)
        .select()
        .single();

    await ActivityService().logTrophiesUpdated();

    return UserProfile.fromJson(Map<String, dynamic>.from(row));
  }

  /// `null` si la colonne n'existe pas encore (script SQL non exécuté).
  Future<List<String>?> fetchPantheonIds(String profileId) async {
    try {
      final cached = await cachedProfileRow(profileId);
      final Map<String, dynamic>? row;
      if (cached != null && cached.containsKey('pantheon_item_ids')) {
        row = cached;
      } else {
        row = await _client
            .from('profiles')
            .select('pantheon_item_ids')
            .eq('id', profileId)
            .maybeSingle();
      }
      final raw = row?['pantheon_item_ids'];
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).where((id) => id.isNotEmpty).toList();
    } on PostgrestException catch (e) {
      if (_isMissingColumnError(e) || e.message.contains('pantheon_item_ids')) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> savePantheonIds(List<String> ids) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');
    final trimmed = ids.where((e) => e.isNotEmpty).take(20).toList();
    invalidateCachedProfile(id);
    await _client.from('profiles').update({
      'pantheon_item_ids': trimmed,
    }).eq('id', id);
  }

  Future<void> updateCollectionPrivacy({
    required bool hideFromNonFriends,
    required bool hideFromFriends,
  }) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    invalidateCachedProfile(id);
    await _client.from('profiles').update({
      'hide_collection_from_non_friends': hideFromNonFriends,
      'hide_collection_from_friends': hideFromFriends,
    }).eq('id', id);
  }

  /// Genre et accord des salutations. Ignoré si les colonnes ne sont pas
  /// encore créées (voir schema_profile_greeting.sql). N'écrit jamais null.
  Future<void> saveGreetingProfile({
    required String identity,
    required String grammar,
  }) async {
    final id = _userId;
    if (id == null) return;
    final safeIdentity = identity.trim();
    final safeGrammar = grammar.trim();
    if (safeIdentity.isEmpty || safeGrammar.isEmpty) return;
    invalidateCachedProfile(id);
    try {
      await _client.from('profiles').update({
        'gender_identity': safeIdentity,
        'greeting_grammar': safeGrammar,
      }).eq('id', id);
    } catch (_) {}
  }

  Future<({String? identity, String? grammar})> fetchGreetingProfile() async {
    final id = _userId;
    if (id == null) return (identity: null, grammar: null);
    try {
      final cached = await cachedProfileRow(id);
      final Map<String, dynamic>? row;
      if (cached != null && cached.containsKey('gender_identity')) {
        row = cached;
      } else {
        row = await _client
            .from('profiles')
            .select('gender_identity, greeting_grammar')
            .eq('id', id)
            .maybeSingle();
      }
      if (row == null) return (identity: null, grammar: null);
      final identity = row['gender_identity'] as String?;
      final grammar = row['greeting_grammar'] as String?;
      return (
        identity: identity != null && identity.trim().isNotEmpty
            ? identity
            : null,
        grammar: grammar != null && grammar.trim().isNotEmpty ? grammar : null,
      );
    } catch (_) {
      return (identity: null, grammar: null);
    }
  }
}
