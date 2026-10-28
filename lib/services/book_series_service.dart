import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/book_series.dart';
import '../models/book_subcategory.dart';
import '../models/book_volume.dart';
import '../models/collection_item.dart';
import '../models/collection_category.dart';
import '../utils/book_series_normalizer.dart';
import '../utils/book_title_parser.dart';
import 'anilist_manga_service.dart';
import 'book_catalog_service.dart';
import 'book_intelligence_service.dart';
import 'itunes_books_service.dart';
import 'mangadex_service.dart';
import 'open_library_service.dart';
import 'profile_service.dart';

class BookSeriesService {
  final _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  static bool _isSubcategoryCheckFailure(Object e) {
    if (e is PostgrestException) {
      if (e.code == '23514') return true;
      final m = e.message.toLowerCase();
      return m.contains('subcategory_check');
    }
    final s = e.toString().toLowerCase();
    return s.contains('23514') || s.contains('subcategory_check');
  }

  Future<Map<String, dynamic>> _insertCollectionItem(
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _client
          .from('collection_items')
          .insert(payload)
          .select()
          .single();
    } on PostgrestException catch (e) {
      if (!_isSubcategoryCheckFailure(e)) rethrow;
      final raw = payload['subcategory']?.toString();
      final fallback = switch (raw) {
        'comics' => 'comic',
        'roman' => 'novel',
        'bd' => 'comic',
        _ => null,
      };
      if (fallback == null || fallback == raw) rethrow;
      payload = Map<String, dynamic>.from(payload)..['subcategory'] = fallback;
      return await _client
          .from('collection_items')
          .insert(payload)
          .select()
          .single();
    }
  }

  Future<List<BookSeries>> fetchSeries({
    required BookSubcategory subcategory,
    String? parentSeriesId,
    bool rootsOnly = false,
  }) async {
    var query = _client
        .from('book_series')
        .select()
        .eq('owner_id', _userId)
        .eq('subcategory', subcategory.dbValue);

    if (rootsOnly) {
      query = query.filter('parent_series_id', 'is', null);
    } else if (parentSeriesId != null) {
      query = query.eq('parent_series_id', parentSeriesId);
    }

    final rows = await query.order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(BookSeries.fromJson)
        .toList();
  }

  Future<BookSeries?> fetchSeriesById(String id) async {
    final row = await _client
        .from('book_series')
        .select()
        .eq('id', id)
        .eq('owner_id', _userId)
        .maybeSingle();
    if (row == null) return null;
    return BookSeries.fromJson(row);
  }

  Future<BookSeries> createSeries({
    required String name,
    required BookSubcategory subcategory,
    String? parentSeriesId,
    int? expectedVolumeCount,
    String? coverUrl,
    String? author,
  }) async {
    await ProfileService().ensureCurrentUserProfile();

    final meta = <String, dynamic>{};
    final a = author?.trim();
    if (a != null && a.isNotEmpty) meta['author'] = a;

    final payload = <String, dynamic>{
      'owner_id': _userId,
      'name': name.trim(),
      'subcategory': subcategory.dbValue,
      'parent_series_id': parentSeriesId,
      'expected_volume_count': expectedVolumeCount,
      'cover_url': coverUrl,
      if (meta.isNotEmpty) 'metadata': meta,
    };
    Map<String, dynamic> row;
    try {
      row = await _client.from('book_series').insert(payload).select().single();
    } on PostgrestException catch (e) {
      if (!_isSubcategoryCheckFailure(e)) rethrow;
      final fallback = subcategory.legacyDbValue;
      if (fallback == subcategory.dbValue) rethrow;
      payload['subcategory'] = fallback;
      row = await _client.from('book_series').insert(payload).select().single();
    }

    final series = BookSeries.fromJson(row);
    if (expectedVolumeCount != null && expectedVolumeCount > 0) {
      await ensureVolumeSlots(series.id, expectedVolumeCount);
    }
    return series;
  }

  /// Persiste l’auteur API sur la série si manquant.
  Future<BookSeries> ensureSeriesAuthor(
    BookSeries series,
    String? author,
  ) async {
    final a = author?.trim();
    if (a == null || a.isEmpty) return series;
    if (series.author != null && series.author!.isNotEmpty) {
      // Complète seulement si vide ; sinon conserve l’auteur déjà choisi.
      return series;
    }
    final updated = series.withAuthor(a);
    await updateSeries(updated);
    return updated;
  }

  Future<void> updateSeries(BookSeries series) async {
    final payload = series.toUpdateJson();
    try {
      await _client
          .from('book_series')
          .update(payload)
          .eq('id', series.id)
          .eq('owner_id', _userId);
    } on PostgrestException catch (e) {
      if (!_isSubcategoryCheckFailure(e)) rethrow;
      final fallback = series.subcategory.legacyDbValue;
      if (fallback == series.subcategory.dbValue) rethrow;
      payload['subcategory'] = fallback;
      await _client
          .from('book_series')
          .update(payload)
          .eq('id', series.id)
          .eq('owner_id', _userId);
    }
  }

  Future<void> deleteSeries(String id) async {
    await _client
        .from('book_series')
        .delete()
        .eq('id', id)
        .eq('owner_id', _userId);
  }

  Future<void> setSeriesWishlist(String seriesId, bool value) async {
    await _client
        .from('book_series')
        .update({'wishlist_entire_series': value})
        .eq('id', seriesId)
        .eq('owner_id', _userId);
  }

  Future<List<BookVolume>> fetchVolumes(String seriesId) async {
    final rows = await _client
        .from('book_volumes')
        .select()
        .eq('series_id', seriesId)
        .order('sort_index');
    return List<Map<String, dynamic>>.from(rows)
        .map(BookVolume.fromJson)
        .toList();
  }

  /// Charge séries + volumes + items en 3 requêtes (plus de N+1).
  Future<
      ({
        List<BookSeries> series,
        Map<String, List<BookVolume>> volumesBySeries,
        Map<String, List<CollectionItem>> itemsBySeries,
      })> fetchCollectionBundle() async {
    final series = await fetchAllRootSeries();
    if (series.isEmpty) {
      return (
        series: series,
        volumesBySeries: <String, List<BookVolume>>{},
        itemsBySeries: <String, List<CollectionItem>>{},
      );
    }
    final ids = series.map((s) => s.id).toList();

    final volRows = await _client
        .from('book_volumes')
        .select()
        .inFilter('series_id', ids)
        .order('sort_index');
    final volumesBySeries = <String, List<BookVolume>>{};
    for (final row in List<Map<String, dynamic>>.from(volRows)) {
      final v = BookVolume.fromJson(row);
      volumesBySeries.putIfAbsent(v.seriesId, () => []).add(v);
    }

    final itemRows = await _client
        .from('collection_items')
        .select()
        .eq('category', 'book')
        .inFilter('series_id', ids);
    final itemsBySeries = <String, List<CollectionItem>>{};
    for (final row in List<Map<String, dynamic>>.from(itemRows)) {
      final item = CollectionItem.fromJson(row);
      if (item.addedBy != _userId && item.locationUserId != _userId) {
        continue;
      }
      final sid = item.seriesId;
      if (sid == null) continue;
      itemsBySeries.putIfAbsent(sid, () => []).add(item);
    }

    return (
      series: series,
      volumesBySeries: volumesBySeries,
      itemsBySeries: itemsBySeries,
    );
  }

  static bool isMangaDexCoverUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = url.toLowerCase();
    return u.contains('mangadex');
  }

  /// Applique couvertures + dates VF (GB écrase MangaDex).
  Future<int> applyVolumeCoversFromMap({
    required String seriesId,
    required Map<int, String> coverByVolume,
    Map<int, String>? publishedDatesByVolume,
  }) async {
    if (coverByVolume.isEmpty &&
        (publishedDatesByVolume == null || publishedDatesByVolume.isEmpty)) {
      return 0;
    }
    final volumes = await fetchVolumes(seriesId);
    var n = 0;
    for (final v in volumes) {
      final num = v.volumeNumber.round();
      final url = coverByVolume[num];
      final pub = publishedDatesByVolume?[num];
      final upcoming =
          BookIntelligenceService.isFuturePublishedDate(pub);
      final hasVerified = v.coverUrl != null &&
          v.coverUrl!.isNotEmpty &&
          v.metadata['cover_volume_verified'] == num;
      // GB/iTunes VF écrase toujours MD **et** d'anciennes couvs IT sauvées.
      final overwriteWithCatalog = url != null &&
          url.isNotEmpty &&
          !isMangaDexCoverUrl(url);

      final hasCover = v.coverUrl != null && v.coverUrl!.isNotEmpty;
      final existingMd = isMangaDexCoverUrl(v.coverUrl);
      final incomingMd = url != null && isMangaDexCoverUrl(url);
      // MangaDex ne remplit qu'un tome vide. Une VF écrase une couv. MD.
      final allowCover = url != null &&
          url.isNotEmpty &&
          url != v.coverUrl &&
          (!hasCover || (existingMd && !incomingMd));
      if (allowCover && (!hasVerified || overwriteWithCatalog || existingMd)) {
        await setVolumeCoverUrl(
          v.id,
          url,
          verifiedVolume: num,
          publishedDate: pub,
          upcoming: pub != null ? upcoming : null,
        );
        n++;
        continue;
      }
      if (pub != null && pub.isNotEmpty) {
        await patchVolumePublishedDate(
          v.id,
          publishedDate: pub,
          upcoming: upcoming,
        );
        n++;
      }
    }
    return n;
  }

  Future<void> patchVolumePublishedDate(
    String volumeId, {
    required String publishedDate,
    required bool upcoming,
  }) async {
    final row = await _client
        .from('book_volumes')
        .select('metadata')
        .eq('id', volumeId)
        .maybeSingle();
    if (row == null) return;
    final meta = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    meta['published_date'] = publishedDate;
    if (upcoming) {
      meta['is_upcoming'] = true;
    } else {
      meta.remove('is_upcoming');
    }
    await _client
        .from('book_volumes')
        .update({'metadata': meta})
        .eq('id', volumeId);
  }

  /// Met à jour expected_volume_count si de nouveaux tomes sont détectés.
  Future<BookSeries?> bumpExpectedCountIfHigher(
    BookSeries series,
    int candidate,
  ) async {
    if (candidate < 1) return series;
    final cur = series.expectedVolumeCount ?? 0;
    if (candidate <= cur) return series;
    await ensureVolumeSlots(series.id, candidate);
    final updated = series.copyWith(expectedVolumeCount: candidate);
    await updateSeries(updated);
    return updated;
  }

  /// Interroge Google Books / iTunes (« [série] Tome ») pour nouveaux tomes + couvs.
  Future<BookSeries> refreshPublications(BookSeries series) async {
    final query = '${series.name.trim()} Tome';
    final raw = await BookCatalogService.searchBooks(
      query,
      subcategory: series.subcategory,
      filters: BookSearchFilters(titleQuery: series.name),
    );
    final hits = BookIntelligenceService.dedupeBySeriesVolume(
      BookIntelligenceService.enrichAndRank(
        raw,
        subcategory: series.subcategory,
        filters: BookSearchFilters(titleQuery: series.name),
      ),
    );
    final covers = <int, String>{};
    var maxVol = series.expectedVolumeCount ?? 0;
    final seriesAuthor = series.author;
    for (final h in hits) {
      final title = h.raw['title'] ?? h.displayTitle;
      if (BookSeriesNormalizer.looksLikeChapterOrScan(title)) continue;
      if (!BookSeriesNormalizer.hitBelongsToSeries(title, series.name)) {
        continue;
      }
      if (!BookSeriesNormalizer.authorMatchesExpected(h.author, seriesAuthor)) {
        continue;
      }
      final n = h.parsed.volumeNumber?.round();
      if (n != null && n > 0) {
        if (n > maxVol) maxVol = n;
        final img = h.imageUrl;
        if (img != null && img.isNotEmpty) {
          covers.putIfAbsent(n, () => img);
        }
      }
    }
    // Manga : covers VF d'abord ; MangaDex complète (y compris suite JP).
    var workingSeries = series;
    if (workingSeries.subcategory == BookSubcategory.manga) {
      final ani = await AnilistMangaService.lookupManga(workingSeries.name);
      if (ani != null) {
        if (ani.volumes != null && ani.volumes! > maxVol) {
          maxVol = ani.volumes!;
        }
        if ((seriesAuthor == null || seriesAuthor.isEmpty) &&
            ani.author != null &&
            ani.author!.isNotEmpty) {
          workingSeries =
              await ensureSeriesAuthor(workingSeries, ani.author!);
        }
      }
      final md = await MangaDexService.lookupManga(
        workingSeries.name,
        authorHint: workingSeries.author ?? seriesAuthor,
      );
      if (md != null) {
        final mdVols = md.volumesPublished ?? 0;
        if (mdVols > maxVol) maxVol = mdVols;
        for (final e in md.coverByVolume.entries) {
          // VF (hits) déjà dans covers → putIfAbsent garde la VF.
          covers.putIfAbsent(e.key, () => e.value);
        }
        if ((workingSeries.author == null || workingSeries.author!.isEmpty) &&
            md.author != null &&
            md.author!.isNotEmpty) {
          workingSeries = await ensureSeriesAuthor(workingSeries, md.author!);
        }
      }
    }
    var updated = workingSeries;
    if (maxVol > (workingSeries.expectedVolumeCount ?? 0)) {
      updated =
          (await bumpExpectedCountIfHigher(workingSeries, maxVol)) ??
              workingSeries;
    }
    if (covers.isNotEmpty) {
      await applyVolumeCoversFromMap(
        seriesId: updated.id,
        coverByVolume: covers,
      );
    }
    return (await fetchSeriesById(updated.id)) ?? updated;
  }

  /// Ne contacte jamais Google Books. L'enrichissement est réservé à la fiche série.
  Future<BookSeries> ensureRealisticVolumeCount(BookSeries series) async {
    return series;
  }

  /// Séries `other` qui sont des romans → `novel` (badge Roman).
  Future<BookSeries> reclassifyOtherAsNovelIfLikely(BookSeries series) async {
    if (series.subcategory != BookSubcategory.other) return series;
    final updated = series.copyWith(subcategory: BookSubcategory.novel);
    await updateSeries(updated);
    try {
      await _client
          .from('collection_items')
          .update({'subcategory': BookSubcategory.novel.dbValue})
          .eq('series_id', series.id)
          .eq('category', 'book');
    } catch (_) {}
    return (await fetchSeriesById(series.id)) ?? updated;
  }

  /// AniList/MangaDex confirme un manga → reclasse BD/Autre → Manga.
  Future<BookSeries> reclassifyAsMangaIfConfirmed(BookSeries series) async {
    if (series.subcategory == BookSubcategory.manga) return series;
    if (series.subcategory != BookSubcategory.bd &&
        series.subcategory != BookSubcategory.other &&
        series.subcategory != BookSubcategory.novel) {
      return series;
    }
    try {
      final md = await MangaDexService.lookupManga(
        series.name,
        authorHint: series.author,
      );
      final ani = await AnilistMangaService.lookupManga(series.name);
      final confirmed = md != null || ani != null;
      if (!confirmed) return series;
      // Auteur : si AniList/MD a un auteur et la série aussi, exiger match faible.
      final officialAuthor = md?.author ?? ani?.author;
      if (series.author != null &&
          series.author!.trim().isNotEmpty &&
          officialAuthor != null &&
          officialAuthor.trim().isNotEmpty &&
          !BookSeriesNormalizer.authorsMatch(series.author!, officialAuthor)) {
        // Titre exact quand même → reclasse (Berserk / Glénat).
        final q = BookSeriesNormalizer.mergeKey(series.name);
        final t = BookSeriesNormalizer.mergeKey(md?.title ?? ani?.title ?? '');
        if (q != t) return series;
      }
      final vols = [
        series.expectedVolumeCount ?? 0,
        md?.volumesPublished ?? 0,
        ani?.volumes ?? 0,
      ].reduce((a, b) => a > b ? a : b);
      var updated = series.copyWith(
        subcategory: BookSubcategory.manga,
        expectedVolumeCount: vols > 0 ? vols : series.expectedVolumeCount,
      );
      await updateSeries(updated);
      if (vols > 1) {
        await ensureVolumeSlots(updated.id, vols);
      }
      // Items liés : subcategory manga.
      try {
        await _client
            .from('collection_items')
            .update({'subcategory': BookSubcategory.manga.dbValue})
            .eq('series_id', series.id)
            .eq('category', 'book');
      } catch (_) {}
      return (await fetchSeriesById(series.id)) ?? updated;
    } catch (_) {
      return series;
    }
  }

  Future<void> ensureVolumeSlots(String seriesId, int count) async {
    if (count < 1) return;
    final existing = await fetchVolumes(seriesId);
    final existingNums = existing.map((v) => v.volumeNumber).toSet();
    final toInsert = <Map<String, dynamic>>[];
    for (var i = 1; i <= count; i++) {
      final n = i.toDouble();
      if (existingNums.contains(n)) continue;
      toInsert.add({
        'series_id': seriesId,
        'volume_number': n,
        'sort_index': n,
        'label': 'Tome $i',
      });
    }
    if (toInsert.isNotEmpty) {
      await _client.from('book_volumes').insert(toInsert);
    }
  }

  Future<List<CollectionItem>> fetchSeriesItems(String seriesId) async {
    final rows = await _client
        .from('collection_items')
        .select()
        .eq('category', 'book')
        .eq('series_id', seriesId);
    return List<Map<String, dynamic>>.from(rows)
        .map(CollectionItem.fromJson)
        .where((i) =>
            i.addedBy == _userId || i.locationUserId == _userId)
        .toList();
  }

  Future<BookSeries> findOrCreateStandaloneSeries({
    required String bookTitle,
    required BookSubcategory subcategory,
    String? coverUrl,
  }) async {
    final name = bookTitle.trim();
    if (name.isEmpty) throw ArgumentError('Titre requis');

    final existing = await findSeriesByName(name, subcategory);
    if (existing != null) {
      await ensureVolumeSlots(existing.id, 1);
      if (coverUrl != null &&
          coverUrl.isNotEmpty &&
          (existing.coverUrl == null || existing.coverUrl!.isEmpty)) {
        await updateSeries(existing.copyWith(coverUrl: coverUrl));
      }
      if (!existing.isStandalone) {
        final meta = Map<String, dynamic>.from(existing.metadata);
        meta['is_standalone'] = true;
        await updateSeries(existing.copyWith(metadata: meta));
      }
      return (await fetchSeriesById(existing.id)) ?? existing;
    }

    final series = await createSeries(
      name: name,
      subcategory: subcategory,
      expectedVolumeCount: 1,
      coverUrl: coverUrl,
    );
    await updateSeries(
      series.copyWith(
        metadata: {...series.metadata, 'is_standalone': true},
      ),
    );
    return (await fetchSeriesById(series.id)) ?? series;
  }

  Future<({String seriesId, String volumeId})> resolveStandaloneBook({
    required String bookTitle,
    required BookSubcategory subcategory,
    String? coverUrl,
  }) async {
    final series = await findOrCreateStandaloneSeries(
      bookTitle: bookTitle,
      subcategory: subcategory,
      coverUrl: coverUrl,
    );
    final vol = await getOrCreateVolume(series.id, 1);
    if (coverUrl != null && coverUrl.isNotEmpty) {
      await setVolumeCoverUrl(vol.id, coverUrl);
    }
    return (seriesId: series.id, volumeId: vol.id);
  }

  /// Rattache les livres orphelins : parse série/tome si possible, sinon standalone.
  Future<int> ensureStandaloneSeriesForUnassigned() async {
    var migrated = 0;
    for (final sub in BookSubcategory.values) {
      final unassigned = await fetchUnassignedBooks(sub);
      for (final item in unassigned) {
        final fromTitle = await resolveSeriesFromTitle(
          title: item.title,
          subcategory: sub,
          coverUrl: item.imageUrl,
        );
        if (fromTitle != null) {
          final volId = fromTitle.volumeId ??
              (await getOrCreateVolume(fromTitle.seriesId, 1)).id;
          await linkItemToVolume(
            itemId: item.id,
            seriesId: fromTitle.seriesId,
            volumeId: volId,
          );
        } else {
          final resolved = await resolveStandaloneBook(
            bookTitle: item.title,
            subcategory: sub,
            coverUrl: item.imageUrl,
          );
          await linkItemToVolume(
            itemId: item.id,
            seriesId: resolved.seriesId,
            volumeId: resolved.volumeId,
          );
        }
        migrated++;
      }
    }
    // Fusionne les dossiers « Thorgal - Tome N » éclatés en une seule série.
    migrated += await regroupExplodedSeriesFolders();
    return migrated;
  }

  /// Fusionne les séries dont le nom est un titre de tome (« X - Tome N »)
  /// dans le dossier canonique de la série.
  Future<int> regroupExplodedSeriesFolders() async {
    var merged = 0;
    for (final sub in BookSubcategory.values) {
      final all = await fetchSeries(subcategory: sub, rootsOnly: true);
      for (final series in List<BookSeries>.from(all)) {
        final parsed = BookSeriesNormalizer.parse(series.name);
        if (!parsed.hasSeries || !parsed.hasVolume) continue;

        final volCeil = parsed.volumeNumber!.ceil();
        final expected = (series.expectedVolumeCount ?? 0) > volCeil
            ? series.expectedVolumeCount
            : volCeil;

        final canonical = await findOrCreateSeries(
          name: parsed.seriesName!,
          subcategory: sub,
          expectedVolumeCount: expected,
          coverUrl: series.coverUrl,
        );
        if (canonical.id == series.id) {
          // Renomme le dossier tome → nom de série.
          if (series.name.trim() != parsed.seriesName!.trim()) {
            await updateSeries(
              series.copyWith(
                name: parsed.seriesName!.trim(),
                expectedVolumeCount: expected,
              ),
            );
          }
          continue;
        }

        if (expected != null && expected > 0) {
          await ensureVolumeSlots(canonical.id, expected);
        }
        final vol = await getOrCreateVolume(canonical.id, parsed.volumeNumber!);
        final items = await fetchSeriesItems(series.id);
        for (final item in items) {
          await linkItemToVolume(
            itemId: item.id,
            seriesId: canonical.id,
            volumeId: vol.id,
          );
        }
        // Transfère aussi les volumes orphelins restants.
        final oldVolumes = await fetchVolumes(series.id);
        for (final ov in oldVolumes) {
          if (ov.volumeNumber == parsed.volumeNumber) continue;
          final target = await getOrCreateVolume(canonical.id, ov.volumeNumber);
          if (ov.coverUrl != null &&
              ov.coverUrl!.isNotEmpty &&
              (target.coverUrl == null || target.coverUrl!.isEmpty)) {
            await setVolumeCoverUrl(target.id, ov.coverUrl!);
          }
        }
        try {
          await deleteSeries(series.id);
        } catch (_) {}
        merged++;
      }
    }
    return merged;
  }

  Future<List<CollectionItem>> fetchAllBooks() async {
    final rows = await _client
        .from('collection_items')
        .select()
        .eq('category', 'book');

    return List<Map<String, dynamic>>.from(rows)
        .map(CollectionItem.fromJson)
        .where((i) =>
            i.addedBy == _userId || i.locationUserId == _userId)
        .toList();
  }

  Future<List<CollectionItem>> fetchUnassignedBooks(
    BookSubcategory subcategory,
  ) async {
    final rows = await _client
        .from('collection_items')
        .select()
        .eq('category', 'book')
        .eq('subcategory', subcategory.dbValue)
        .filter('series_id', 'is', null);

    return List<Map<String, dynamic>>.from(rows)
        .map(CollectionItem.fromJson)
        .where((i) =>
            i.addedBy == _userId || i.locationUserId == _userId)
        .toList();
  }

  BookSeriesStats computeStats({
    required BookSeries series,
    required List<BookVolume> volumes,
    required List<CollectionItem> items,
  }) {
    final active = items.where((i) => !i.isSold).toList();
    final owned = active.where((i) => !i.isWishlist).toList();
    final wishlistItems = active.where((i) => i.isWishlist).toList();

    final volById = {for (final v in volumes) v.id: v};
    var totalSlots = series.expectedVolumeCount ?? 0;
    final regularVols = volumes.where((v) => !v.isHorsSerie).toList();
    if (totalSlots < regularVols.length) totalSlots = regularVols.length;
    if (totalSlots == 0 && regularVols.isNotEmpty) {
      totalSlots = regularVols.length;
    }

    // Possédés = numéros de tome distincts (jamais de 73/42).
    final ownedNumbers = <int>{};
    for (final i in owned) {
      final vol = i.volumeId != null ? volById[i.volumeId!] : null;
      if (vol == null || vol.isHorsSerie) continue;
      final n = vol.volumeNumber.round();
      if (totalSlots > 0 && n > totalSlots) continue;
      if (n >= 1) ownedNumbers.add(n);
    }
    final ownedCount = ownedNumbers.length;

    // Lus = tous les tomes marqués lus (possédés OU non).
    final readNumbers = <int>{};
    for (final i in active) {
      if (!i.isRead) continue;
      final vol = i.volumeId != null ? volById[i.volumeId!] : null;
      if (vol == null || vol.isHorsSerie) continue;
      final n = vol.volumeNumber.round();
      if (n >= 1) readNumbers.add(n);
    }
    for (final v in volumes) {
      if (!v.isRead || v.isHorsSerie) continue;
      final n = v.volumeNumber.round();
      if (n >= 1) readNumbers.add(n);
    }
    final readCount = readNumbers.length;

    // Moyenne perso UNIQUEMENT sur notes > 0.
    double? rating = series.userRating;
    if (rating != null && rating <= 0) rating = null;
    if (rating == null) {
      final rated = active
          .where((i) => i.rating != null && i.rating! > 0)
          .map((i) => i.rating! > 5.0 ? i.rating! / 2 : i.rating!)
          .toList();
      if (rated.isNotEmpty) {
        rating = rated.reduce((a, b) => a + b) / rated.length;
      }
    }
    final community = series.communityRating;

    var totalNew = series.totalNewValue ?? 0;
    var totalUsed = series.totalUsedValue ?? 0;
    if (totalNew == 0 && totalUsed == 0) {
      for (final i in owned) {
        final meta = i.metadata ?? {};
        totalNew += _num(meta['value_new']);
        totalUsed += _num(meta['value_used']);
        if (i.purchasePrice != null) totalUsed += i.purchasePrice!;
      }
    }

    final wishNumbers = <int>{};
    for (final i in wishlistItems) {
      final vol = i.volumeId != null ? volById[i.volumeId!] : null;
      if (vol == null || vol.isHorsSerie) continue;
      wishNumbers.add(vol.volumeNumber.round());
    }
    final wishlistCount =
        series.wishlistEntireSeries ? totalSlots : wishNumbers.length;

    return BookSeriesStats(
      ownedCount: ownedCount,
      readCount: readCount,
      wishlistVolumeCount: wishlistCount,
      totalSlots: totalSlots,
      displayRating: rating,
      communityRating: community,
      totalNewValue: totalNew,
      totalUsedValue: totalUsed,
    );
  }

  /// Hydrate note communauté (AniList / GB) si absente.
  Future<BookSeries> hydrateCommunityRating(BookSeries series) async {
    if (series.communityRating != null) return series;
    double? onFive;
    if (series.subcategory == BookSubcategory.manga) {
      final meta = await AnilistMangaService.lookupManga(series.name);
      onFive = meta?.ratingOnFive;
    }
    if (onFive == null || onFive <= 0) return series;
    final meta = Map<String, dynamic>.from(series.metadata);
    meta['community_rating'] =
        double.parse(onFive.toStringAsFixed(2));
    final updated = series.copyWith(metadata: meta);
    await updateSeries(updated);
    return updated;
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  List<BookVolumeSlot> buildVolumeSlots({
    required BookSeries series,
    required List<BookVolume> volumes,
    required List<CollectionItem> items,
  }) {
    final byVolumeId = <String, CollectionItem>{};
    for (final i in items) {
      if (i.volumeId != null) byVolumeId[i.volumeId!] = i;
    }

    final slots = volumes.map((v) {
      final item = byVolumeId[v.id];
      BookVolumeStatus status;
      if (series.wishlistEntireSeries) {
        status = BookVolumeStatus.wishlist;
      } else if (item != null) {
        status =
            item.isWishlist ? BookVolumeStatus.wishlist : BookVolumeStatus.owned;
      } else {
        status = BookVolumeStatus.missing;
      }
      return BookVolumeSlot(volume: v, item: item, status: status);
    }).toList();

    // Items liés par numéro dans metadata sans volume_id
    return slots;
  }

  Future<void> setVolumeReadFlag(String volumeId, bool isRead) async {
    final row = await _client
        .from('book_volumes')
        .select('metadata')
        .eq('id', volumeId)
        .maybeSingle();
    if (row == null) return;
    final meta = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    if (isRead) {
      meta['is_read'] = true;
    } else {
      meta.remove('is_read');
    }
    await _client
        .from('book_volumes')
        .update({'metadata': meta})
        .eq('id', volumeId);
  }

  Future<void> setVolumeCoverUrl(
    String volumeId,
    String coverUrl, {
    int? verifiedVolume,
    String? publishedDate,
    bool? upcoming,
    double? communityRating,
  }) async {
    if (coverUrl.isEmpty) return;
    final row = await _client
        .from('book_volumes')
        .select('metadata')
        .eq('id', volumeId)
        .maybeSingle();
    if (row == null) return;
    final meta = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    var url = coverUrl;
    if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
    meta['cover_url'] = url;
    if (verifiedVolume != null) {
      meta['cover_volume_verified'] = verifiedVolume;
    }
    if (publishedDate != null && publishedDate.isNotEmpty) {
      meta['published_date'] = publishedDate;
    }
    if (upcoming != null) {
      if (upcoming) {
        meta['is_upcoming'] = true;
      } else {
        meta.remove('is_upcoming');
      }
    }
    if (communityRating != null && communityRating > 0) {
      meta['community_rating'] =
          double.parse(communityRating.clamp(0, 5).toStringAsFixed(2));
    }
    await _client
        .from('book_volumes')
        .update({'metadata': meta})
        .eq('id', volumeId);
  }

  /// Efface une couverture erronée (hors-série / mauvais tome).
  Future<void> clearVolumeCover(String volumeId) async {
    final row = await _client
        .from('book_volumes')
        .select('metadata')
        .eq('id', volumeId)
        .maybeSingle();
    if (row == null) return;
    final meta = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    meta.remove('cover_url');
    meta.remove('cover_volume_verified');
    await _client
        .from('book_volumes')
        .update({'metadata': meta})
        .eq('id', volumeId);
  }

  Future<void> patchVolumeMetadata(
    String volumeId,
    Map<String, dynamic> patch,
  ) async {
    final row = await _client
        .from('book_volumes')
        .select('metadata')
        .eq('id', volumeId)
        .maybeSingle();
    if (row == null) return;
    final meta = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    meta.addAll(patch);
    await _client
        .from('book_volumes')
        .update({'metadata': meta})
        .eq('id', volumeId);
  }

  /// Couvertures : Google Books FR d'abord (écrase MangaDex), MD comble les trous.
  /// [onProgress] est appelé tous les [progressEvery] tomes trouvés (UI live).
  Future<int> enrichMissingVolumeCovers({
    required BookSeries series,
    required List<BookVolume> volumes,
    int maxLookups = 40,
    bool repairUnverified = true,
    void Function(int foundSinceStart)? onProgress,
    int progressEvery = 5,
  }) async {
    var updated = 0;
    var sinceProgress = 0;

    var working = series;
    var seriesAuthor = working.author;

    final batch = <int, ({String coverUrl, String? publishedDate})>{};
    var vfMax = 0;

    // 1) Google Books FR = source de vérité VF (covers + dates + max tome).
    // Jusqu'à 3×40 = 120 items pour couvrir Berserk (43+) malgré 503 partiels.
    try {
      final expected = working.expectedVolumeCount ?? volumes.length;
      final pagesNeeded = expected > 40 ? 3 : (expected > 20 ? 2 : 2);
      final gb = await BookIntelligenceService.batchFetchSeriesCovers(
        seriesName: working.name,
        subcategory: working.subcategory,
        authorHint: seriesAuthor,
        maxPages: pagesNeeded.clamp(1, 3),
      );
      for (final e in gb.entries) {
        batch[e.key] = e.value;
        if (e.key > vfMax) vfMax = e.key;
      }
    } catch (_) {}

    // 2) Apple Books FR avant MangaDex (mangas inclus) — 1 recherche, pas 1/tome.
    try {
      final itunes = await ItunesBooksService.search(working.name, limit: 50);
      for (final h in itunes) {
        final title = h['title'] ?? '';
        if (!BookSeriesNormalizer.hitBelongsToSeries(title, working.name)) {
          continue;
        }
        final n = BookTitleParser.extractVolumeNumberStrict(title);
        if (n == null || n < 1) continue;
        final img = h['image_url'] ?? '';
        if (img.isEmpty || isMangaDexCoverUrl(img)) continue;
        batch.putIfAbsent(
          n,
          () => (coverUrl: img, publishedDate: h['published_date']),
        );
        if (n > vfMax) vfMax = n;
      }
    } catch (_) {}

    // 3) MangaDex comble TOUS les trous restants (T25, T28, T31-39…).
    if (working.subcategory == BookSubcategory.manga) {
      try {
        final md = await MangaDexService.lookupManga(
          working.name,
          authorHint: seriesAuthor,
        );
        if (md != null) {
          var covers = Map<int, String>.from(md.coverByVolume);
          final need = md.volumesPublished ??
              (working.expectedVolumeCount ?? volumes.length);
          if (covers.length < need && md.id.isNotEmpty) {
            try {
              final extra = await MangaDexService.fetchAllCovers(md.id);
              covers.addAll(extra);
            } catch (_) {}
          }
          for (final e in covers.entries) {
            batch.putIfAbsent(
              e.key,
              () => (coverUrl: e.value, publishedDate: null),
            );
          }
          final mdVols = md.volumesPublished;
          final batchMax = batch.isEmpty
              ? 0
              : batch.keys.reduce((a, b) => a > b ? a : b);
          final target = [
            working.expectedVolumeCount ?? 0,
            vfMax,
            mdVols ?? 0,
            batchMax,
            covers.isEmpty ? 0 : covers.keys.reduce((a, b) => a > b ? a : b),
          ].reduce((a, b) => a > b ? a : b);
          if (target > (working.expectedVolumeCount ?? 0)) {
            working =
                (await bumpExpectedCountIfHigher(working, target)) ?? working;
          }
          if ((seriesAuthor == null || seriesAuthor.isEmpty) &&
              md.author != null &&
              md.author!.isNotEmpty) {
            working = await ensureSeriesAuthor(working, md.author!);
            seriesAuthor = working.author;
          }
        }
      } catch (_) {}
    } else if (vfMax > (working.expectedVolumeCount ?? 0)) {
      working = (await bumpExpectedCountIfHigher(working, vfMax)) ?? working;
    }

    final ordered = List<BookVolume>.from(await fetchVolumes(working.id))
      ..sort((a, b) => a.volumeNumber.compareTo(b.volumeNumber));

    for (final vol in ordered) {
      if (vol.isHorsSerie) continue;
      final n = vol.volumeNumber.round();
      final hit = batch[n];
      final hasCover = vol.coverUrl != null && vol.coverUrl!.isNotEmpty;

      if (hit == null) continue;

      final url = hit.coverUrl;
      final pub = hit.publishedDate;
      final upcoming = BookIntelligenceService.isFuturePublishedDate(pub);
      final incomingMd = isMangaDexCoverUrl(url);
      final existingMd = isMangaDexCoverUrl(vol.coverUrl);
      final sameCover = hasCover && vol.coverUrl == url;
      final dateMissing = pub != null &&
          pub.isNotEmpty &&
          (vol.metadata['published_date'] == null ||
              vol.metadata['published_date'].toString().isEmpty);

      if (sameCover) {
        if (dateMissing) {
          await patchVolumePublishedDate(
            vol.id,
            publishedDate: pub,
            upcoming: upcoming,
          );
          updated++;
        }
        continue;
      }

      // MangaDex : trou vide seulement, jamais par-dessus une couverture.
      if (incomingMd) {
        if (hasCover) continue;
      } else if (hasCover && !existingMd) {
        // Couverture VF déjà en base : on la garde.
        continue;
      }

      await setVolumeCoverUrl(
        vol.id,
        url,
        verifiedVolume: n,
        publishedDate: pub,
        upcoming: upcoming,
      );
      updated++;
      sinceProgress++;
      if (onProgress != null &&
          progressEvery > 0 &&
          sinceProgress % progressEvery == 0) {
        onProgress(updated);
      }
    }

    // Couverture série = Tome 1 seulement si vide / non verrouillée.
    final fresh = await fetchSeriesById(working.id);
    final refreshed = await fetchVolumes(working.id);
    String? tome1;
    for (final v in refreshed) {
      if (v.volumeNumber >= 0.99 &&
          v.volumeNumber < 1.01 &&
          v.coverUrl != null &&
          v.coverUrl!.isNotEmpty) {
        tome1 = v.coverUrl;
        break;
      }
    }
    if (fresh != null &&
        !fresh.coverLocked &&
        (fresh.coverUrl == null || fresh.coverUrl!.isEmpty) &&
        tome1 != null &&
        tome1.isNotEmpty) {
      await updateSeries(fresh.copyWith(coverUrl: tome1));
      updated++;
    }
    return updated;
  }

  Future<void> toggleVolumeWishlist({
    required BookSeries series,
    required BookVolumeSlot slot,
    required bool wishlist,
  }) async {
    final items = await fetchSeriesItems(series.id);
    final existing = items
        .where((i) => i.volumeId == slot.volume.id && !i.isSold)
        .toList();
    if (!wishlist) {
      for (final i in existing.where((e) => e.isWishlist)) {
        await removeVolumeItem(i.id);
      }
      return;
    }
    // Déjà possédé → ne pas forcer wishlist.
    if (existing.any((e) => !e.isWishlist)) return;
    if (existing.any((e) => e.isWishlist)) return;

    await ProfileService().ensureCurrentUserProfile();
    final n = slot.volume.volumeNumber.ceil();
    await _insertCollectionItem({
      'title': '${series.name} - Tome $n',
      'category': CollectionCategory.book.dbValue,
      'subcategory': series.subcategory.dbValue,
      'series_id': series.id,
      'volume_id': slot.volume.id,
      'is_wishlist': true,
      'quantity': 1,
      'added_by': _userId,
      'location_user_id': _userId,
      'metadata': {
        if (slot.volume.coverUrl != null) 'image_url': slot.volume.coverUrl,
      },
    });
  }

  Future<void> ensureSeriesCoverFromItem({
    required String seriesId,
    String? imageUrl,
  }) async {
    if (imageUrl == null || imageUrl.isEmpty) return;
    final series = await fetchSeriesById(seriesId);
    if (series == null) return;
    if (series.coverLocked) return;
    if (series.coverUrl != null && series.coverUrl!.isNotEmpty) return;
    await updateSeries(series.copyWith(coverUrl: imageUrl));
  }

  Future<void> linkItemToVolume({
    required String itemId,
    required String seriesId,
    required String volumeId,
  }) async {
    await _client.from('collection_items').update({
      'series_id': seriesId,
      'volume_id': volumeId,
    }).eq('id', itemId);
  }

  Future<List<BookSeries>> fetchAllRootSeries() async {
    final rows = await _client
        .from('book_series')
        .select()
        .eq('owner_id', _userId)
        .filter('parent_series_id', 'is', null)
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(BookSeries.fromJson)
        .toList();
  }

  Future<void> removeVolumeItem(String itemId) async {
    if (!_isPersistedItemId(itemId)) return;
    await _client.from('collection_items').delete().eq('id', itemId);
  }

  Future<CollectionItem> addVolumeQuick({
    required BookSeries series,
    required BookVolume volume,
    bool markAsRead = false,
  }) async {
    await ProfileService().ensureCurrentUserProfile();

    // Anti-doublon : une seule entrée possédée par volume_id.
    final existing = await fetchSeriesItems(series.id);
    final dupes = existing
        .where((i) => i.volumeId == volume.id && !i.isWishlist && !i.isSold)
        .toList();
    if (dupes.isNotEmpty) {
      final keep = dupes.first;
      for (final d in dupes.skip(1)) {
        await removeVolumeItem(d.id);
      }
      if (markAsRead && !keep.isRead) {
        await setItemRead(keep.id, true);
      }
      return keep;
    }

    final n = volume.volumeNumber.ceil();
    final customTitle = volume.volumeTitle;
    final title = customTitle != null && customTitle.isNotEmpty
        ? '${series.name} — $customTitle'
        : '${series.name} - Tome $n';
    final read = markAsRead || volume.isRead;
    final row = await _insertCollectionItem({
      'title': title,
      'category': CollectionCategory.book.dbValue,
      'subcategory': series.subcategory.dbValue,
      'series_id': series.id,
      'volume_id': volume.id,
      'is_wishlist': false,
      'is_read': read,
      'quantity': 1,
      'added_by': _userId,
      'location_user_id': _userId,
      'metadata': {
        if (volume.metadata['cover_url'] != null)
          'image_url': volume.metadata['cover_url'],
      },
    });
    if (read) {
      await setVolumeReadFlag(volume.id, false);
    }
    final coverUrl = volume.coverUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      await ensureSeriesCoverFromItem(seriesId: series.id, imageUrl: coverUrl);
    }
    return CollectionItem.fromJson(row);
  }

  Future<void> toggleVolumeOwned({
    required BookSeries series,
    required BookVolumeSlot slot,
    required bool owned,
  }) async {
    if (owned) {
      await addVolumeQuick(series: series, volume: slot.volume);
      return;
    }
    // Supprime TOUTES les lignes pour ce volume (anti 73/42).
    final items = await fetchSeriesItems(series.id);
    final toRemove = items
        .where((i) =>
            i.volumeId == slot.volume.id && !i.isWishlist && !i.isSold)
        .toList();
    var keepReadFlag = false;
    for (final item in toRemove) {
      if (item.isRead) keepReadFlag = true;
      await removeVolumeItem(item.id);
    }
    if (keepReadFlag) {
      await setVolumeReadFlag(slot.volume.id, true);
    }
  }

  /// Déduplique les `collection_items` d'une série (1 ligne / volume_id).
  Future<int> dedupeVolumeItems(String seriesId) async {
    final items = await fetchSeriesItems(seriesId);
    final byVol = <String, List<CollectionItem>>{};
    for (final i in items) {
      if (i.volumeId == null || i.isWishlist || i.isSold) continue;
      byVol.putIfAbsent(i.volumeId!, () => []).add(i);
    }
    var removed = 0;
    for (final list in byVol.values) {
      if (list.length < 2) continue;
      list.sort((a, b) {
        final ar = a.isRead ? 1 : 0;
        final br = b.isRead ? 1 : 0;
        if (ar != br) return br.compareTo(ar);
        return a.id.compareTo(b.id);
      });
      for (final extra in list.skip(1)) {
        await removeVolumeItem(extra.id);
        removed++;
      }
    }
    return removed;
  }

  /// Fusionne toutes les séries au même nom normalisé → 1 seule ligne.
  Future<int> dedupeDuplicateSeriesFolders() async {
    final all = await fetchAllRootSeries();
    final groups = <String, List<BookSeries>>{};
    for (final s in all) {
      final key = BookSeriesNormalizer.mergeKey(s.name);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(s);
    }

    var merged = 0;
    for (final entry in groups.entries) {
      final list = entry.value;
      // Aussi fusionner un seul dossier mal nommé « Thorgal - Tome ».
      final needsRename = list.length == 1 &&
          BookSeriesNormalizer.parse(list.first.name).hasVolume;
      if (list.length < 2 && !needsRename) continue;

      list.sort((a, b) {
        final aScore = _seriesCanonicalScore(a);
        final bScore = _seriesCanonicalScore(b);
        return bScore.compareTo(aScore);
      });
      final canonical = list.first;
      var expected = canonical.expectedVolumeCount ?? 0;
      for (final s in list) {
        final e = s.expectedVolumeCount ?? 0;
        if (e > expected) expected = e;
      }
      if (expected < 1) expected = 1;

      final canonName = BookSeriesNormalizer.displaySeriesName(canonical.name);
      await updateSeries(
        canonical.copyWith(
          name: canonName,
          subcategory: canonical.subcategory,
          expectedVolumeCount: expected,
          metadata: {
            ...canonical.metadata,
            'is_standalone': expected <= 1,
          },
        ),
      );
      if (expected > 0) await ensureVolumeSlots(canonical.id, expected);

      for (final dup in list.skip(1)) {
        final items = await fetchSeriesItems(dup.id);
        for (final item in items) {
          final parsed = BookSeriesNormalizer.parse(item.title);
          double? fromOldVol;
          if (item.volumeId != null) {
            final oldVols = await fetchVolumes(dup.id);
            for (final v in oldVols) {
              if (v.id == item.volumeId) {
                fromOldVol = v.volumeNumber;
                break;
              }
            }
          }
          final volNum = parsed.volumeNumber ?? fromOldVol ?? 1.0;
          final vol = await getOrCreateVolume(canonical.id, volNum);
          await linkItemToVolume(
            itemId: item.id,
            seriesId: canonical.id,
            volumeId: vol.id,
          );
        }
        final oldVols = await fetchVolumes(dup.id);
        for (final ov in oldVols) {
          final target =
              await getOrCreateVolume(canonical.id, ov.volumeNumber);
          if (ov.coverUrl != null &&
              ov.coverUrl!.isNotEmpty &&
              (target.coverUrl == null || target.coverUrl!.isEmpty)) {
            await setVolumeCoverUrl(target.id, ov.coverUrl!);
          }
        }
        try {
          await deleteSeries(dup.id);
        } catch (_) {}
        merged++;
      }

      await dedupeVolumeItems(canonical.id);
      // Persiste le nom nettoyé même sans doublon.
      if (list.length == 1 && list.first.name.trim() != canonName) {
        await updateSeries(
          (await fetchSeriesById(canonical.id))!.copyWith(
            name: canonName,
            expectedVolumeCount: expected,
          ),
        );
      }
    }
    return merged;
  }

  int _seriesCanonicalScore(BookSeries s) {
    var score = 0;
    if (!s.isStandalone) score += 100;
    score += (s.expectedVolumeCount ?? 0);
    if (s.coverUrl != null && s.coverUrl!.isNotEmpty) score += 20;
    if (s.subcategory == BookSubcategory.novel) score -= 30;
    return score;
  }

  /// Nettoie les doublons de tomes d'une série (menu « Réinitialiser »).
  Future<({int removedDupes, int ownedLeft})> cleanupSeriesVolumes(
    String seriesId,
  ) async {
    final removed = await dedupeVolumeItems(seriesId);
    final items = await fetchSeriesItems(seriesId);
    final owned =
        items.where((i) => !i.isWishlist && !i.isSold).length;
    return (removedDupes: removed, ownedLeft: owned);
  }

  /// Supprime tous les tomes possédés (remet la série à 0 possédé).
  Future<int> resetOwnedVolumes(String seriesId) async {
    final items = await fetchSeriesItems(seriesId);
    var n = 0;
    for (final i in items) {
      if (i.isWishlist || i.isSold) continue;
      await removeVolumeItem(i.id);
      n++;
    }
    return n;
  }

  bool _isPersistedItemId(String id) =>
      id.isNotEmpty && !id.startsWith('local-');

  Future<void> setItemRead(String itemId, bool isRead) async {
    if (!_isPersistedItemId(itemId)) return;
    await _client
        .from('collection_items')
        .update({'is_read': isRead})
        .eq('id', itemId);
  }

  Future<void> setItemRating(String itemId, double rating) async {
    if (!_isPersistedItemId(itemId)) return;
    final clamped = double.parse(rating.clamp(0.0, 5.0).toStringAsFixed(1));
    await _client.from('collection_items').update({
      'rating': clamped <= 0 ? null : clamped,
    }).eq('id', itemId);
  }

  Future<void> toggleVolumeRead({
    required BookVolumeSlot slot,
    required bool read,
  }) async {
    // Lu possible sans possession (scan / bibliothèque) via flag volume.
    final item = slot.item;
    if (item != null && !item.isWishlist && _isPersistedItemId(item.id)) {
      await setItemRead(item.id, read);
      await setVolumeReadFlag(slot.volume.id, read);
      return;
    }
    await setVolumeReadFlag(slot.volume.id, read);
  }

  Future<void> setVolumeEdition({
    required String volumeId,
    required BookVolumeEdition edition,
  }) async {
    await patchVolumeMetadata(volumeId, {
      'edition': edition.dbValue,
    });
  }

  /// `fr` | `ja` | `en` — langue de l'exemplaire physique.
  Future<void> setVolumeEditionLanguage({
    required String volumeId,
    required String language,
  }) async {
    await patchVolumeMetadata(volumeId, {
      'edition_language': language,
    });
  }

  /// Nettoie le nom série (« One Piece - Édition originale » → « One Piece »)
  /// et persiste immédiatement en base si différent.
  Future<BookSeries> sanitizeSeriesName(BookSeries series) async {
    final raw = series.name.trim();
    var clean = BookSeriesNormalizer.displaySeriesName(raw);
    if (clean.isEmpty) clean = BookSeriesNormalizer.stripEditionSuffix(raw);
    if (clean.isEmpty) clean = raw;
    if (clean == raw) return series;
    final updated = series.copyWith(name: clean);
    try {
      await updateSeries(updated);
    } catch (_) {
      // Retry minimal : update name seul.
      try {
        await _client
            .from('book_series')
            .update({'name': clean})
            .eq('id', series.id)
            .eq('owner_id', _userId);
      } catch (_) {
        return series;
      }
    }
    return updated;
  }

  Future<BookSeries?> findSeriesByName(
    String name,
    BookSubcategory subcategory,
  ) async {
    final all = await fetchSeries(subcategory: subcategory, rootsOnly: true);
    for (final s in all) {
      if (BookSeriesNormalizer.namesMatch(s.name, name)) return s;
    }
    return null;
  }

  /// Cherche une série par nom dans toutes les sous-catégories.
  Future<BookSeries?> findSeriesByNameAnySub(String name) async {
    final all = await fetchAllRootSeries();
    for (final s in all) {
      if (BookSeriesNormalizer.namesMatch(s.name, name) ||
          BookSeriesNormalizer.mergeKey(s.name) ==
              BookSeriesNormalizer.mergeKey(name)) {
        return s;
      }
    }
    return null;
  }

  Future<BookSeries> findOrCreateSeries({
    required String name,
    required BookSubcategory subcategory,
    int? expectedVolumeCount,
    String? coverUrl,
    String? author,
  }) async {
    // Évite doublons cross-sous-catégorie (même nom normalisé).
    var existing = await findSeriesByName(name, subcategory);
    existing ??= await findSeriesByNameAnySub(name);
    if (existing != null) {
      var updated = existing;
      if (expectedVolumeCount != null &&
          (existing.expectedVolumeCount ?? 0) < expectedVolumeCount) {
        updated = updated.copyWith(expectedVolumeCount: expectedVolumeCount);
        await ensureVolumeSlots(existing.id, expectedVolumeCount);
      }
      if (coverUrl != null &&
          coverUrl.isNotEmpty &&
          (existing.coverUrl == null || existing.coverUrl!.isEmpty)) {
        updated = updated.copyWith(coverUrl: coverUrl);
      }
      // Auteur dynamique depuis la recherche (si pas encore stocké).
      if (author != null &&
          author.trim().isNotEmpty &&
          (updated.author == null || updated.author!.isEmpty)) {
        updated = updated.withAuthor(author);
      }
      // Retire le flag standalone si multi-tomes.
      final exp = updated.expectedVolumeCount ?? expectedVolumeCount ?? 0;
      if (exp > 1 && existing.metadata['is_standalone'] == true) {
        final meta = Map<String, dynamic>.from(updated.metadata);
        meta['is_standalone'] = false;
        updated = updated.copyWith(metadata: meta);
      }
      // Persiste le nom nettoyé (« One Piece - Édition originale » → « One Piece »).
      final clean = BookSeriesNormalizer.displaySeriesName(updated.name);
      if (clean != updated.name.trim()) {
        updated = updated.copyWith(name: clean);
      }
      if (updated != existing) await updateSeries(updated);
      return (await fetchSeriesById(updated.id)) ?? updated;
    }
    return createSeries(
      name: BookSeriesNormalizer.displaySeriesName(name),
      subcategory: subcategory,
      expectedVolumeCount: expectedVolumeCount,
      coverUrl: coverUrl,
      author: author,
    );
  }

  Future<BookVolume> getOrCreateVolume(
    String seriesId,
    double volumeNumber,
  ) async {
    final volumes = await fetchVolumes(seriesId);
    for (final v in volumes) {
      if (v.volumeNumber == volumeNumber) return v;
    }
    final label = volumeNumber == volumeNumber.roundToDouble()
        ? 'Tome ${volumeNumber.toInt()}'
        : 'Tome $volumeNumber';
    final row = await _client
        .from('book_volumes')
        .insert({
          'series_id': seriesId,
          'volume_number': volumeNumber,
          'sort_index': volumeNumber,
          'label': label,
        })
        .select()
        .single();
    return BookVolume.fromJson(row);
  }

  /// Crée ou met à jour série + tome à partir du titre du livre.
  Future<({String seriesId, String? volumeId, String itemTitle})?>
      resolveSeriesFromTitle({
    required String title,
    required BookSubcategory subcategory,
    int? estimatedTotalVolumes,
    String? coverUrl,
    String? author,
  }) async {
    var parsed = BookSeriesNormalizer.parse(title);
    // Titre nu (« Kingdom ») → dossier série si estimate fourni ou nom utile.
    if (!parsed.hasSeries) {
      final clean = BookSeriesNormalizer.displaySeriesName(title);
      final hasEstimate =
          estimatedTotalVolumes != null && estimatedTotalVolumes > 1;
      if (hasEstimate || clean.length >= 2) {
        parsed = ParsedBookTitle(
          rawTitle: title,
          seriesName: clean.isNotEmpty ? clean : title.trim(),
        );
      } else {
        return null;
      }
    } else {
      parsed = ParsedBookTitle(
        rawTitle: parsed.rawTitle,
        seriesName: BookSeriesNormalizer.displaySeriesName(parsed.seriesName!),
        volumeNumber: parsed.volumeNumber,
      );
    }

    // Ne JAMAIS plafonner au seul tome X ajouté : total VF de la série.
    final solidVfEstimate =
        estimatedTotalVolumes != null && estimatedTotalVolumes >= 1;
    var total = estimatedTotalVolumes;
    final volCeil = parsed.volumeNumber?.ceil() ?? 0;

    if (!solidVfEstimate || (total != null && total < volCeil)) {
      // Batch GB FR avant MangaDex (évite de s'arrêter au tome X).
      try {
        final gb = await BookIntelligenceService.batchFetchSeriesCovers(
          seriesName: parsed.seriesName!,
          subcategory: subcategory,
          authorHint: author,
          maxPages: subcategory == BookSubcategory.manga ? 2 : 3,
        );
        if (gb.isNotEmpty) {
          final gbMax = gb.keys.reduce((a, b) => a > b ? a : b);
          if (gbMax > (total ?? 0)) total = gbMax;
        }
      } catch (_) {}
    }

    // Hybrid : max(VF, MangaDex JP) pour garder la suite VO (ex. T12).
    if (subcategory == BookSubcategory.manga) {
      try {
        final fromDex =
            await MangaDexService.lookupManga(parsed.seriesName!);
        final dexVols = fromDex?.volumesPublished;
        if (dexVols != null && dexVols > (total ?? 0)) total = dexVols;
      } catch (_) {}
      if (total == null || total < volCeil) {
        final fromAni = await AnilistMangaService.estimateVolumeCount(
          parsed.seriesName!,
        );
        if (fromAni != null && fromAni > (total ?? 0)) total = fromAni;
      }
    }
    if (total == null || total < volCeil) {
      final fromOl = await OpenLibraryService.estimateSeriesVolumeCount(
        parsed.seriesName!,
        subcategory,
      );
      if (fromOl != null && fromOl > (total ?? 0)) {
        total = fromOl;
      } else if (volCeil > 0 && (total == null || total < volCeil)) {
        total = volCeil;
      }
    }
    final vfEst = estimatedTotalVolumes;
    if (vfEst != null && vfEst > (total ?? 0)) {
      total = vfEst;
    }
    if (total != null && volCeil > total) total = volCeil;

    final series = await findOrCreateSeries(
      name: parsed.seriesName!,
      subcategory: subcategory,
      expectedVolumeCount: total,
      coverUrl: coverUrl,
      author: author,
    );

    if (total != null && total > 0) {
      await ensureVolumeSlots(series.id, total);
    } else if (volCeil > 0) {
      await ensureVolumeSlots(series.id, volCeil);
    }

    String? volumeId;
    if (parsed.hasVolume) {
      final vol = await getOrCreateVolume(series.id, parsed.volumeNumber!);
      volumeId = vol.id;
      if (coverUrl != null &&
          coverUrl.isNotEmpty &&
          (vol.coverUrl == null || vol.coverUrl!.isEmpty)) {
        await setVolumeCoverUrl(vol.id, coverUrl);
      }
    }

    return (
      seriesId: series.id,
      volumeId: volumeId,
      itemTitle: parsed.itemTitle,
    );
  }

  Future<List<CollectionItem>> fetchAllBooksInSubcategory(
    BookSubcategory subcategory,
  ) async {
    final rows = await _client
        .from('collection_items')
        .select()
        .eq('category', 'book')
        .eq('subcategory', subcategory.dbValue);

    return List<Map<String, dynamic>>.from(rows)
        .map(CollectionItem.fromJson)
        .where((i) =>
            i.addedBy == _userId || i.locationUserId == _userId)
        .toList();
  }

  /// Marque une plage de tomes comme possédés (crée des entrées minimales).
  Future<int> markVolumesOwned({
    required BookSeries series,
    required int fromVolume,
    required int toVolume,
    bool markAsRead = false,
  }) async {
    final low = fromVolume < toVolume ? fromVolume : toVolume;
    final high = fromVolume < toVolume ? toVolume : fromVolume;
    final numbers = [for (var n = low; n <= high; n++) n];
    return markVolumesOwnedNumbers(
      series: series,
      volumeNumbers: numbers,
      markAsRead: markAsRead,
    );
  }

  /// Marque une liste de numéros de tomes (sélection multiple).
  Future<int> markVolumesOwnedNumbers({
    required BookSeries series,
    required List<int> volumeNumbers,
    bool markAsRead = false,
  }) async {
    if (volumeNumbers.isEmpty) return 0;

    await ProfileService().ensureCurrentUserProfile();

    final unique = volumeNumbers.toSet().toList()..sort();
    final maxNum = unique.last;
    final cap = maxNum > (series.expectedVolumeCount ?? 0)
        ? maxNum
        : (series.expectedVolumeCount ?? maxNum);
    if (cap > 0) {
      await ensureVolumeSlots(series.id, cap);
      if ((series.expectedVolumeCount ?? 0) < cap) {
        await updateSeries(
          series.copyWith(expectedVolumeCount: cap),
        );
      }
    }

    final existing = await fetchSeriesItems(series.id);
    final byVolumeId = {
      for (final i in existing)
        if (i.volumeId != null) i.volumeId!: i,
    };

    var created = 0;
    for (final n in unique) {
      final vol = await getOrCreateVolume(series.id, n.toDouble());
      if (byVolumeId.containsKey(vol.id)) continue;

      final title = '${series.name} - Tome $n';
      await _insertCollectionItem({
        'title': title,
        'category': CollectionCategory.book.dbValue,
        'subcategory': series.subcategory.dbValue,
        'series_id': series.id,
        'volume_id': vol.id,
        'is_wishlist': false,
        'is_read': markAsRead,
        'quantity': 1,
        'added_by': _userId,
        'location_user_id': _userId,
        'metadata': {},
      });
      created++;
    }
    return created;
  }

  Future<void> recomputeSeriesValues(String seriesId) async {
    final series = await fetchSeriesById(seriesId);
    if (series == null) return;
    final items = await fetchSeriesItems(seriesId);
    var totalNew = 0.0;
    var totalUsed = 0.0;
    for (final i in items.where((x) => !x.isWishlist && !x.isSold)) {
      final meta = i.metadata ?? {};
      totalNew += _num(meta['value_new']);
      totalUsed += _num(meta['value_used']);
      if (i.purchasePrice != null) totalUsed += i.purchasePrice!;
    }
    final meta = Map<String, dynamic>.from(series.metadata);
    meta['total_value_new'] = totalNew;
    meta['total_value_used'] = totalUsed;
    await updateSeries(series.copyWith(metadata: meta));
  }

  Future<double> _nextHorsSerieNumber(String seriesId) async {
    final volumes = await fetchVolumes(seriesId);
    final hors = volumes
        .where((v) => v.isHorsSerie)
        .map((v) => v.volumeNumber)
        .toList();
    if (hors.isEmpty) return -1;
    return hors.reduce((a, b) => a < b ? a : b) - 1;
  }

  Future<void> updateVolumeMetadata(
    String volumeId,
    Map<String, dynamic> patch,
  ) async {
    final row = await _client
        .from('book_volumes')
        .select('metadata, label')
        .eq('id', volumeId)
        .maybeSingle();
    if (row == null) return;
    final meta = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    meta.addAll(patch);
    final updates = <String, dynamic>{'metadata': meta};
    final title = patch['volume_title']?.toString();
    if (title != null && title.isNotEmpty) {
      updates['label'] = title;
    }
    await _client.from('book_volumes').update(updates).eq('id', volumeId);
  }

  /// Crée un tome manuel (hors-série ou placeholder futur).
  Future<BookVolume> createManualVolume({
    required BookSeries series,
    String? volumeNumberText,
    required String title,
    String? description,
    String? coverUrl,
    bool owned = false,
    bool read = false,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) throw ArgumentError('Titre requis');

    final isHorsSerie =
        volumeNumberText == null || volumeNumberText.trim().isEmpty;
    late final double volumeNumber;
    late final double sortIndex;
    late final String label;

    if (isHorsSerie) {
      volumeNumber = await _nextHorsSerieNumber(series.id);
      sortIndex = 10000 + volumeNumber.abs();
      label = trimmedTitle;
    } else {
      volumeNumber = double.parse(volumeNumberText.trim().replaceAll(',', '.'));
      sortIndex = volumeNumber;
      label = 'Tome ${volumeNumber.round()}';
    }

    final existing = await fetchVolumes(series.id);
    if (!isHorsSerie) {
      final dup = existing.where(
        (v) =>
            !v.isHorsSerie &&
            (v.volumeNumber - volumeNumber).abs() < 0.01 &&
            !v.isManualPlaceholder,
      );
      if (dup.isNotEmpty) {
        throw StateError('Le tome ${volumeNumber.round()} existe déjà');
      }
    }

    final meta = <String, dynamic>{
      'volume_title': trimmedTitle,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (isHorsSerie) 'is_hors_serie': true,
      if (!isHorsSerie) 'is_manual_placeholder': true,
      if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
      if (read) 'is_read': true,
    };

    final row = await _client
        .from('book_volumes')
        .insert({
          'series_id': series.id,
          'volume_number': volumeNumber,
          'sort_index': sortIndex,
          'label': label,
          'metadata': meta,
        })
        .select()
        .single();

    final volume = BookVolume.fromJson(row);
    if (!isHorsSerie && volumeNumber > (series.expectedVolumeCount ?? 0)) {
      await updateSeries(
        series.copyWith(expectedVolumeCount: volumeNumber.ceil()),
      );
    }
    if (owned) {
      await addVolumeQuick(
        series: series,
        volume: volume,
        markAsRead: read,
      );
    }
    return volume;
  }

  /// Fusionne les placeholders quand le catalogue officiel les reconnaît.
  Future<String?> fuseManualPlaceholders({required BookSeries series}) async {
    final volumes = await fetchVolumes(series.id);
    final placeholders = volumes.where((v) => v.isManualPlaceholder).toList();
    if (placeholders.isEmpty) return null;

    final batch = await BookIntelligenceService.batchFetchSeriesCovers(
      seriesName: series.name,
      subcategory: series.subcategory,
      authorHint: series.author,
      maxPages: 2,
    );

    for (final ph in placeholders) {
      final hit = batch[ph.volumeNumber.round()];
      final cover = hit?.coverUrl;
      if (cover == null || cover.isEmpty) continue;

      final meta = Map<String, dynamic>.from(ph.metadata);
      meta
        ..remove('is_manual_placeholder')
        ..['cover_url'] = cover;

      await _client.from('book_volumes').update({
        'metadata': meta,
        if (ph.volumeTitle != null) 'label': ph.volumeTitle,
      }).eq('id', ph.id);

      return 'Hé, on dirait qu\'un nouveau tome officiel est sorti ! '
          'Ton exemplaire (T.${ph.displayNumber}) a été fusionné.';
    }
    return null;
  }
}
