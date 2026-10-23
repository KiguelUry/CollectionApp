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
import 'mangadex_service.dart';
import 'open_library_service.dart';
import 'profile_service.dart';

class BookSeriesService {
  final _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

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
  }) async {
    await ProfileService().ensureCurrentUserProfile();

    final row = await _client
        .from('book_series')
        .insert({
          'owner_id': _userId,
          'name': name.trim(),
          'subcategory': subcategory.dbValue,
          'parent_series_id': parentSeriesId,
          'expected_volume_count': expectedVolumeCount,
          'cover_url': coverUrl,
        })
        .select()
        .single();

    final series = BookSeries.fromJson(row);
    if (expectedVolumeCount != null && expectedVolumeCount > 0) {
      await ensureVolumeSlots(series.id, expectedVolumeCount);
    }
    return series;
  }

  Future<void> updateSeries(BookSeries series) async {
    await _client
        .from('book_series')
        .update(series.toUpdateJson())
        .eq('id', series.id)
        .eq('owner_id', _userId);
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

  /// Applique les couvertures découvertes en recherche (série → tome → url).
  Future<int> applyVolumeCoversFromMap({
    required String seriesId,
    required Map<int, String> coverByVolume,
  }) async {
    if (coverByVolume.isEmpty) return 0;
    final volumes = await fetchVolumes(seriesId);
    var n = 0;
    for (final v in volumes) {
      final num = v.volumeNumber.round();
      final url = coverByVolume[num];
      if (url == null || url.isEmpty) continue;
      if (v.coverUrl != null &&
          v.coverUrl!.isNotEmpty &&
          v.metadata['cover_volume_verified'] == num) {
        continue;
      }
      await setVolumeCoverUrl(v.id, url, verifiedVolume: num);
      n++;
    }
    return n;
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
    final dict = BookSeriesNormalizer.expectedCount(
          series.name,
          series.subcategory,
        ) ??
        0;
    if (dict > maxVol) maxVol = dict;
    for (final h in hits) {
      final n = h.parsed.volumeNumber?.round();
      if (n != null && n > 0) {
        if (n > maxVol) maxVol = n;
        final img = h.imageUrl;
        if (img != null && img.isNotEmpty) {
          covers.putIfAbsent(n, () => img);
        }
      }
      final est = h.estimatedTotalVolumes;
      if (est != null && est > maxVol) maxVol = est;
    }
    var updated = series;
    if (maxVol > (series.expectedVolumeCount ?? 0)) {
      updated = (await bumpExpectedCountIfHigher(series, maxVol)) ?? series;
    }
    // Force Thorgal → BD.
    final preferred = BookSeriesNormalizer.preferredSubcategory(updated.name);
    if (preferred != null && preferred != updated.subcategory) {
      updated = updated.copyWith(subcategory: preferred);
      await updateSeries(updated);
    }
    if (covers.isNotEmpty) {
      await applyVolumeCoversFromMap(
        seriesId: updated.id,
        coverByVolume: covers,
      );
    }
    return (await fetchSeriesById(updated.id)) ?? updated;
  }

  /// Si manga/BD/comics (ou roman multi) a ≤1 tome déclaré, sonde le catalogue.
  Future<BookSeries> ensureRealisticVolumeCount(BookSeries series) async {
    final preferred = BookSeriesNormalizer.preferredSubcategory(series.name);
    var cur = series;
    if (preferred != null && preferred != cur.subcategory) {
      cur = cur.copyWith(subcategory: preferred);
      await updateSeries(cur);
    }
    final isSerial = cur.subcategory == BookSubcategory.manga ||
        cur.subcategory == BookSubcategory.comic ||
        cur.subcategory == BookSubcategory.comics ||
        BookSeriesNormalizer.expectedCount(cur.name, cur.subcategory) != null;
    if (!isSerial) return cur;
    if ((cur.expectedVolumeCount ?? 0) > 1) return cur;
    return refreshPublications(cur);
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

        final known = BookSeriesNormalizer.expectedCount(parsed.seriesName!, sub);
        final volCeil = parsed.volumeNumber!.ceil();
        final expected = known ??
            ((series.expectedVolumeCount ?? 0) > volCeil
                ? series.expectedVolumeCount
                : volCeil);

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

    final readNumbers = <int>{};
    for (final i in owned) {
      if (!i.isRead) continue;
      final vol = i.volumeId != null ? volById[i.volumeId!] : null;
      if (vol == null || vol.isHorsSerie) continue;
      final n = vol.volumeNumber.round();
      if (n >= 1) readNumbers.add(n);
    }
    for (final v in volumes) {
      if (!v.isRead || v.isHorsSerie) continue;
      final n = v.volumeNumber.round();
      if (ownedNumbers.contains(n)) readNumbers.add(n);
    }
    final readCount = readNumbers.length;

    double? rating = series.userRating;
    if (rating == null) {
      final rated = owned.where((i) => i.rating != null).toList();
      if (rated.isNotEmpty) {
        rating = rated.map((i) => i.rating!).reduce((a, b) => a + b) /
            rated.length;
      }
    }

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
      totalNewValue: totalNew,
      totalUsedValue: totalUsed,
    );
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

  /// Couvertures manquantes + réparation des mauvaises attributions (T1≠T16).
  Future<int> enrichMissingVolumeCovers({
    required BookSeries series,
    required List<BookVolume> volumes,
    int maxLookups = 40,
    bool repairUnverified = true,
  }) async {
    var updated = 0;
    var lookups = 0;

    // Batch « Série Tome » — uniquement hits au numéro STRICT.
    final batchCovers = <int, String>{};
    final batchPub = <int, String>{};
    try {
      final batch = await BookCatalogService.searchBooks(
        '${series.name} Tome',
        subcategory: series.subcategory,
        filters: BookSearchFilters(titleQuery: series.name),
      );
      final ranked = BookIntelligenceService.enrichAndRank(
        batch,
        subcategory: series.subcategory,
        filters: BookSearchFilters(titleQuery: series.name),
      );
      for (final h in ranked) {
        final img = h.imageUrl;
        if (img == null || img.isEmpty) continue;
        final n = BookTitleParser.extractVolumeNumberStrict(
          '${h.raw['title'] ?? ''} ${h.raw['subtitle'] ?? ''}',
        );
        if (n == null || n < 1) continue;
        if (!BookIntelligenceService.hitMatchesVolumeExactly(h, n)) continue;
        batchCovers.putIfAbsent(n, () => img);
        final pub = h.raw['published_date'] ?? h.raw['year'];
        if (pub != null && pub.isNotEmpty) {
          batchPub.putIfAbsent(n, () => pub);
        }
      }
    } catch (_) {}

    for (final vol in volumes) {
      if (lookups >= maxLookups) break;
      if (vol.isHorsSerie) continue;
      final n = vol.volumeNumber.round();
      final verified = vol.metadata['cover_volume_verified'];
      final hasCover = vol.coverUrl != null && vol.coverUrl!.isNotEmpty;
      final needsRepair = repairUnverified &&
          hasCover &&
          (verified == null || verified != n);
      // Toujours revalider les premiers tomes (bug Naruto/Thorgal T1).
      final forceCheck = n <= 3 && (needsRepair || !hasCover || verified != n);
      if (hasCover && !needsRepair && !forceCheck) continue;

      lookups++;
      String? url = batchCovers[n];
      String? pub = batchPub[n];
      var upcoming = false;
      if (url == null) {
        final meta = await BookIntelligenceService.lookupVolumeCoverMeta(
          seriesName: series.name,
          volumeNumber: vol.volumeNumber,
          subcategory: series.subcategory,
        );
        url = meta.coverUrl;
        pub = meta.publishedDate;
        upcoming = meta.upcoming;
      } else {
        upcoming = BookIntelligenceService.isFuturePublishedDate(pub);
      }

      if (url != null && url.isNotEmpty) {
        await setVolumeCoverUrl(
          vol.id,
          url,
          verifiedVolume: n,
          publishedDate: pub,
          upcoming: upcoming,
        );
        updated++;
      } else if (pub != null) {
        await patchVolumeMetadata(vol.id, {
          'published_date': pub,
          if (upcoming) 'is_upcoming': true,
        });
      }
    }

    // Couverture série = Tome 1 vérifié (jamais un autre tome).
    final fresh = await fetchSeriesById(series.id);
    final refreshed = await fetchVolumes(series.id);
    String? tome1;
    for (final v in refreshed) {
      if (v.volumeNumber >= 0.99 &&
          v.volumeNumber < 1.01 &&
          v.coverUrl != null &&
          v.coverUrl!.isNotEmpty &&
          v.metadata['cover_volume_verified'] == 1) {
        tome1 = v.coverUrl;
        break;
      }
    }
    if (tome1 == null) {
      for (final v in refreshed) {
        if (v.volumeNumber >= 0.99 &&
            v.volumeNumber < 1.01 &&
            v.coverUrl != null &&
            v.coverUrl!.isNotEmpty) {
          tome1 = v.coverUrl;
          break;
        }
      }
    }
    if (fresh != null &&
        tome1 != null &&
        tome1.isNotEmpty &&
        fresh.coverUrl != tome1) {
      await updateSeries(fresh.copyWith(coverUrl: tome1));
      updated++;
    } else if (fresh != null &&
        (fresh.coverUrl == null || fresh.coverUrl!.isEmpty) &&
        tome1 != null) {
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
    await _client.from('collection_items').insert({
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
    final row = await _client
        .from('collection_items')
        .insert({
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
        })
        .select()
        .single();
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
      final preferredSub =
          BookSeriesNormalizer.preferredSubcategory(canonical.name) ??
              canonical.subcategory;
      final known = BookSeriesNormalizer.expectedCount(canonical.name);
      var expected = known ?? canonical.expectedVolumeCount ?? 0;
      for (final s in list) {
        final e = s.expectedVolumeCount ?? 0;
        if (e > expected) expected = e;
      }
      if (expected < 1) expected = 1;

      final canonName = BookSeriesNormalizer.displaySeriesName(canonical.name);
      await updateSeries(
        canonical.copyWith(
          name: canonName,
          subcategory: preferredSub,
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
      // Corrige sous-catégorie BD connue même sans doublon.
      if (list.length == 1 && preferredSub != list.first.subcategory) {
        await updateSeries(
          (await fetchSeriesById(canonical.id))!.copyWith(
            subcategory: preferredSub,
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
    final pref = BookSeriesNormalizer.preferredSubcategory(s.name);
    if (pref != null && s.subcategory == pref) score += 50;
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

  Future<void> setItemRead(String itemId, bool isRead) async {
    await _client
        .from('collection_items')
        .update({'is_read': isRead})
        .eq('id', itemId);
  }

  Future<void> setItemRating(String itemId, double rating) async {
    final clamped = double.parse(rating.clamp(0.0, 5.0).toStringAsFixed(1));
    await _client.from('collection_items').update({
      'rating': clamped <= 0 ? null : clamped,
    }).eq('id', itemId);
  }

  Future<void> toggleVolumeRead({
    required BookVolumeSlot slot,
    required bool read,
  }) async {
    final item = slot.item;
    if (item != null && !item.isWishlist) {
      await setItemRead(item.id, read);
      if (!read) {
        await setVolumeReadFlag(slot.volume.id, false);
      }
      return;
    }
    await setVolumeReadFlag(slot.volume.id, read);
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
  }) async {
    final preferred =
        BookSeriesNormalizer.preferredSubcategory(name) ?? subcategory;
    // Évite Thorgal BD + Thorgal Roman en doublon.
    var existing = await findSeriesByName(name, preferred);
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
      if (preferred != existing.subcategory) {
        updated = updated.copyWith(subcategory: preferred);
      }
      // Retire le flag standalone si multi-tomes.
      final exp = updated.expectedVolumeCount ?? expectedVolumeCount ?? 0;
      if (exp > 1 && existing.metadata['is_standalone'] == true) {
        final meta = Map<String, dynamic>.from(updated.metadata);
        meta['is_standalone'] = false;
        updated = updated.copyWith(metadata: meta);
      }
      if (updated != existing) await updateSeries(updated);
      return (await fetchSeriesById(updated.id)) ?? updated;
    }
    return createSeries(
      name: BookSeriesNormalizer.displaySeriesName(name),
      subcategory: preferred,
      expectedVolumeCount: expectedVolumeCount ??
          BookSeriesNormalizer.expectedCount(name, preferred),
      coverUrl: coverUrl,
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
  }) async {
    var parsed = BookSeriesNormalizer.parse(title);
    // Titre nu d'une série connue (« Thorgal », « Naruto ») → dossier série.
    if (!parsed.hasSeries) {
      final known =
          BookSeriesNormalizer.expectedCount(title.trim(), subcategory);
      if (known != null && known > 1) {
        parsed = ParsedBookTitle(
          rawTitle: title,
          seriesName: title.trim(),
        );
      } else {
        return null;
      }
    }

    var total = estimatedTotalVolumes;
    final volCeil = parsed.volumeNumber?.ceil() ?? 0;
    final known =
        BookSeriesNormalizer.expectedCount(parsed.seriesName!, subcategory);
    if (known != null && (total == null || total < known)) {
      total = known;
    }
    if (total == null || total < volCeil) {
      if (subcategory == BookSubcategory.manga) {
        final fromDex =
            await MangaDexService.lookupManga(parsed.seriesName!);
        final dexVols = fromDex?.volumesPublished;
        if (dexVols != null && dexVols > 1) total = dexVols;
        if (total == null || total < volCeil) {
          final fromAni = await AnilistMangaService.estimateVolumeCount(
            parsed.seriesName!,
          );
          if (fromAni != null && fromAni > 1) total = fromAni;
        }
      }
      if (total == null || total < volCeil) {
        final fromOl = await OpenLibraryService.estimateSeriesVolumeCount(
          parsed.seriesName!,
          subcategory,
        );
        if (fromOl != null) {
          total = fromOl;
        } else if (volCeil > 0) {
          total = volCeil;
        }
      }
    }
    if (total != null && volCeil > total) total = volCeil;

    final series = await findOrCreateSeries(
      name: parsed.seriesName!,
      subcategory: subcategory,
      expectedVolumeCount: total,
      coverUrl: coverUrl,
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
      await _client.from('collection_items').insert({
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

    for (final ph in placeholders) {
      final cover = await BookIntelligenceService.lookupVolumeCover(
        seriesName: series.name,
        volumeNumber: ph.volumeNumber,
        subcategory: series.subcategory,
      );
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
