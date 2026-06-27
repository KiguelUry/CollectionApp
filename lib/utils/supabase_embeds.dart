/// Sélecteurs PostgREST qualifiés (évite PGRST201 après `collection_item_groups`).
abstract final class SupabaseEmbeds {
  static const groupsName = 'groups!collection_items_group_id_fkey(name)';

  static const locationsLabel = 'locations(label)';

  static const addedByProfile =
      'profiles!collection_items_added_by_fkey(username, avatar_url)';

  static const addedByProfileUsername =
      'profiles!collection_items_added_by_fkey(username)';

  static const locationHolderProfile =
      'profiles!collection_items_location_user_id_fkey(username)';

  static const loanedToProfile =
      'profiles!collection_items_loaned_to_id_fkey(username)';

  /// Objet + localisation + groupe principal + détenteur (listes / grilles).
  static const collectionItemList =
      '*, $locationsLabel, $groupsName, location_holder:$locationHolderProfile';

  /// Objet + localisation + groupe principal.
  static const collectionItem =
      '*, $locationsLabel, $groupsName';

  /// Fiche détail complète.
  static const collectionItemDetail =
      '*, $locationsLabel, $groupsName, '
      'location_holder:$locationHolderProfile, '
      'loaned_to:$loanedToProfile, '
      'collection_item_tags(item_tags(id, label, color))';

  /// Prêts actifs.
  static const collectionItemWithLoan =
      '*, $locationsLabel, $groupsName, loaned_to:$loanedToProfile';

  static const groupWantedAuthorProfile =
      'profiles!group_wanted_posts_author_id_fkey(username)';

  static const groupRuleAuthorProfile =
      'profiles!group_rule_entries_author_id_fkey(username)';

  static const groupMemberProfile =
      'profiles!group_members_profile_id_fkey(username, avatar_url, accent_color)';

  static const quickLogItem =
      'collection_items!user_quick_logs_item_id_fkey(title, image_url, category)';
}
