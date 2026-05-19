import 'package:supabase_flutter/supabase_flutter.dart';

/// Filtres pour n'afficher que la collection personnelle de l'utilisateur connecté.
class CollectionItemScope {
  CollectionItemScope._();

  static String? get currentUserId =>
      Supabase.instance.client.auth.currentUser?.id;

  /// Filtre PostgREST : objets perso (hors groupes) du compte connecté.
  static String personalOrFilter(String userId) =>
      'added_by.eq.$userId,location_user_id.eq.$userId';

  /// Applique le périmètre perso sur une requête `collection_items`.
  static PostgrestFilterBuilder personal(
    PostgrestFilterBuilder query, {
    required String userId,
  }) {
    return query
        .filter('group_id', 'is', null)
        .or(personalOrFilter(userId));
  }

  /// Identifiants des groupes dont l'utilisateur est membre.
  static Future<List<String>> myGroupIds(String userId) async {
    final rows = await Supabase.instance.client
        .from('group_members')
        .select('group_id')
        .eq('profile_id', userId);
    return (rows as List).map((r) => r['group_id'] as String).toList();
  }
}
