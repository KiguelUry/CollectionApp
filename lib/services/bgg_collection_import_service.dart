import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/bgg_collection_parse.dart';
import 'bgg_service.dart';
import 'collection_refresh.dart';

enum BggImportPhase { idle, fetching, importing, done, error }

class BggImportProgress {
  final BggImportPhase phase;
  final int total;
  final int processed;
  final int inserted;
  final int alreadyOwned;
  final int skippedExpansions;
  final String? message;

  const BggImportProgress({
    this.phase = BggImportPhase.idle,
    this.total = 0,
    this.processed = 0,
    this.inserted = 0,
    this.alreadyOwned = 0,
    this.skippedExpansions = 0,
    this.message,
  });

  bool get isRunning =>
      phase == BggImportPhase.fetching || phase == BggImportPhase.importing;

  /// `null` = progression indéterminée (attente BGG).
  double? get fraction {
    if (phase == BggImportPhase.done) return 1;
    if (phase != BggImportPhase.importing || total == 0) return null;
    return (processed / total).clamp(0.0, 1.0);
  }

  BggImportProgress copyWith({
    BggImportPhase? phase,
    int? total,
    int? processed,
    int? inserted,
    int? alreadyOwned,
    int? skippedExpansions,
    String? message,
  }) {
    return BggImportProgress(
      phase: phase ?? this.phase,
      total: total ?? this.total,
      processed: processed ?? this.processed,
      inserted: inserted ?? this.inserted,
      alreadyOwned: alreadyOwned ?? this.alreadyOwned,
      skippedExpansions: skippedExpansions ?? this.skippedExpansions,
      message: message ?? this.message,
    );
  }
}

/// Jeux déjà possédés (pour ne pas les réimporter).
class OwnedBoardgames {
  final Set<String> bggIds;
  final List<String> titles;

  const OwnedBoardgames({this.bggIds = const {}, this.titles = const []});
}

typedef BggCollectionFetcher =
    Future<BggCollectionFetchResult> Function(
      String username,
      void Function(String status) onStatus,
    );

CollectionItem collectionItemFromBggEntry(
  BggCollectionEntry e, {
  required String userId,
}) {
  return CollectionItem(
    id: '',
    title: e.title.trim(),
    category: CollectionCategory.boardgame,
    metadata: {
      'bgg_id': e.bggId,
      'year_published': ?e.year,
      'imported_from_bgg': true,
    },
    imageUrl: e.imageUrl ?? e.thumbnailUrl,
    isWishlist: false,
    quantity: 1,
    addedBy: userId,
    locationUserId: userId,
    minPlayers: e.minPlayers,
    maxPlayers: e.maxPlayers,
    playingTime: e.playingTime,
  );
}

/// Import de la collection BGG en tâche de fond (survit à la fermeture
/// de l'écran Paramètres ; la progression est exposée via [progress]).
class BggCollectionImportService {
  BggCollectionImportService({
    BggCollectionFetcher? fetchCollection,
    Future<OwnedBoardgames> Function()? loadOwned,
    Future<void> Function(List<BggCollectionEntry> batch)? insertBatch,
    this.batchSize = 20,
  }) : _fetchCollection = fetchCollection ?? _defaultFetch,
       _loadOwned = loadOwned ?? _defaultLoadOwned,
       _insertBatch = insertBatch ?? _defaultInsertBatch;

  static final instance = BggCollectionImportService();
  static const usernamePrefsKey = 'bgg_import_username';

  final BggCollectionFetcher _fetchCollection;
  final Future<OwnedBoardgames> Function() _loadOwned;
  final Future<void> Function(List<BggCollectionEntry>) _insertBatch;
  final int batchSize;

  final progress = ValueNotifier(const BggImportProgress());
  Future<BggImportProgress>? _running;

  /// Lance l'import ; un second appel pendant l'import renvoie le même futur.
  Future<BggImportProgress> start(String username) {
    return _running ??= _run(
      username.trim(),
    ).whenComplete(() => _running = null);
  }

  void _emit(BggImportProgress p) => progress.value = p;

  Future<BggImportProgress> _run(String username) async {
    if (username.isEmpty) {
      const p = BggImportProgress(
        phase: BggImportPhase.error,
        message: 'Indique ton pseudo BoardGameGeek',
      );
      _emit(p);
      return p;
    }
    _emit(
      const BggImportProgress(
        phase: BggImportPhase.fetching,
        message: 'Récupération de la collection BGG…',
      ),
    );
    try {
      final fetched = await _fetchCollection(username, (status) {
        _emit(progress.value.copyWith(message: status));
      });
      if (fetched.error != null) {
        final p = BggImportProgress(
          phase: BggImportPhase.error,
          message: fetched.error,
        );
        _emit(p);
        return p;
      }

      final owned = await _loadOwned();
      final plan = planBggImport(
        fetched.entries,
        existingBggIds: owned.bggIds,
        existingTitles: owned.titles,
      );
      var p = BggImportProgress(
        phase: BggImportPhase.importing,
        total: plan.toInsert.length,
        alreadyOwned: plan.alreadyOwned.length,
        skippedExpansions: plan.skippedExpansions.length,
        message: plan.toInsert.isEmpty
            ? 'Rien de nouveau à importer'
            : 'Import de ${plan.toInsert.length} jeux…',
      );
      _emit(p);

      for (var i = 0; i < plan.toInsert.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, plan.toInsert.length);
        final batch = plan.toInsert.sublist(i, end);
        await _insertBatch(batch);
        p = p.copyWith(processed: end, inserted: p.inserted + batch.length);
        _emit(p);
      }

      p = p.copyWith(phase: BggImportPhase.done, message: _summary(p));
      _emit(p);
      if (p.inserted > 0) CollectionRefresh.instance.bump();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(usernamePrefsKey, username);
      return p;
    } catch (e) {
      final p = progress.value.copyWith(
        phase: BggImportPhase.error,
        message: 'Import interrompu : $e',
      );
      _emit(p);
      return p;
    }
  }

  static String _summary(BggImportProgress p) {
    final parts = <String>[
      '${p.inserted} jeu${p.inserted > 1 ? 'x' : ''} importé${p.inserted > 1 ? 's' : ''}',
    ];
    if (p.alreadyOwned > 0) {
      parts.add(
        '${p.alreadyOwned} déjà présent${p.alreadyOwned > 1 ? 's' : ''}',
      );
    }
    if (p.skippedExpansions > 0) {
      parts.add(
        '${p.skippedExpansions} extension${p.skippedExpansions > 1 ? 's' : ''} ignorée${p.skippedExpansions > 1 ? 's' : ''}',
      );
    }
    return parts.join(' · ');
  }

  static Future<String?> savedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(usernamePrefsKey);
  }

  static Future<BggCollectionFetchResult> _defaultFetch(
    String username,
    void Function(String) onStatus,
  ) => BggService.fetchUserCollection(username, onStatus: onStatus);

  static Future<OwnedBoardgames> _defaultLoadOwned() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw Exception('Non connecté');
    final rows = await client
        .from('collection_items')
        .select('title, metadata')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .or('added_by.eq.$uid,location_user_id.eq.$uid');
    final ids = <String>{};
    final titles = <String>[];
    for (final r in rows as List) {
      final meta = r['metadata'];
      final id = meta is Map ? meta['bgg_id']?.toString() : null;
      if (id != null && id.isNotEmpty) ids.add(id);
      final t = r['title']?.toString();
      if (t != null) titles.add(t);
    }
    return OwnedBoardgames(bggIds: ids, titles: titles);
  }

  static Future<void> _defaultInsertBatch(
    List<BggCollectionEntry> batch,
  ) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw Exception('Non connecté');
    await client.from('collection_items').insert([
      for (final e in batch)
        collectionItemFromBggEntry(
          e,
          userId: uid,
        ).toInsertJson(isWishlist: false, locationUserId: uid, addedBy: uid),
    ]);
  }
}
