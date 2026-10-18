import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bgg_collection_import_card.dart';

/// Invitation discrète à l'import BGG (1ère ouverture catégorie jeux de société).
class BggCategoryImportPrompt {
  static const _promptKey = 'bgg_import_category_prompt_v1_shown';

  static Future<bool> wasShown() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promptKey) == true) return true;
    try {
      final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
      return meta?['bgg_import_prompt_seen'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptKey, true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'bgg_import_prompt_seen': true}),
      );
    } catch (_) {}
  }

  static Future<void> maybeShow(BuildContext context) async {
    if (!context.mounted) return;
    if (await wasShown()) return;
    if (!context.mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importer ta collection BGG ?'),
        content: const Text(
          'Tu peux synchroniser tes jeux BoardGameGeek en un clic. '
          'Les jeux déjà présents (BGG id ou titre) ne seront pas dupliqués.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'import'),
            child: const Text('Oui, importer'),
          ),
        ],
      ),
    );

    await markShown();
    if (!context.mounted || choice != 'import') return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: BggCollectionImportCard(),
        ),
      ),
    );
  }
}
