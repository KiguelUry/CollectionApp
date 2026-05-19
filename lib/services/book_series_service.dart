import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/book_series.dart';
import '../models/book_subcategory.dart';
import '../models/book_volume.dart';
import '../models/collection_item.dart';
import '../models/collection_category.dart';
import '../models/novel_rating_matrix.dart';
import '../utils/book_title_parser.dart';
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

  Future<void> saveNovelMatrix(String seriesId, NovelRatingMatrix matrix) async {
    final series = await fetchSeriesById(seriesId);
    if (series == null) return;
    final meta = Map<String, dynamic>.from(series.metadata);
    meta.addAll(matrix.toMetadataFragment());
    await updateSeries(series.copyWith(metadata: meta));
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
    final wishlistItems =
        active.where((i) => i.isWishlist).length;
    final read = owned.where((i) => i.isRead).length;

    var totalSlots = series.expectedVolumeCount ?? 0;
    if (totalSlots < volumes.length) totalSlots = volumes.length;
    if (totalSlots == 0 && volumes.isNotEmpty) {
      totalSlots = volumes.length;
    }

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

    final wishlistCount = series.wishlistEntireSeries
        ? totalSlots
        : wishlistItems;

    return BookSeriesStats(
      ownedCount: owned.length,
      readCount: read,
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

  Future<void> setVolumeCoverUrl(String volumeId, String coverUrl) async {
    if (coverUrl.isEmpty) return;
    final row = await _client
        .from('book_volumes')
        .select('metadata')
        .eq('id', volumeId)
        .maybeSingle();
    if (row == null) return;
    final meta = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    meta['cover_url'] = coverUrl;
    await _client
        .from('book_volumes')
        .update({'metadata': meta})
        .eq('id', volumeId);
  }

  /// Récupère les couvertures manquantes via Open Library (max [maxLookups] appels).
  Future<int> enrichMissingVolumeCovers({
    required BookSeries series,
    required List<BookVolume> volumes,
    int maxLookups = 15,
  }) async {
    var updated = 0;
    var lookups = 0;
    for (final vol in volumes) {
      if (lookups >= maxLookups) break;
      if (vol.coverUrl != null && vol.coverUrl!.isNotEmpty) continue;
      lookups++;
      final url = await OpenLibraryService.lookupVolumeCover(
        series.name,
        vol.volumeNumber,
        series.subcategory,
      );
      if (url != null && url.isNotEmpty) {
        await setVolumeCoverUrl(vol.id, url);
        updated++;
      }
    }
    return updated;
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

  Future<void> setItemRead(String itemId, bool isRead) async {
    await _client
        .from('collection_items')
        .update({'is_read': isRead})
        .eq('id', itemId);
  }

  Future<BookSeries?> findSeriesByName(
    String name,
    BookSubcategory subcategory,
  ) async {
    final all = await fetchSeries(subcategory: subcategory, rootsOnly: true);
    for (final s in all) {
      if (BookTitleParser.seriesNamesMatch(s.name, name)) return s;
    }
    return null;
  }

  Future<BookSeries> findOrCreateSeries({
    required String name,
    required BookSubcategory subcategory,
    int? expectedVolumeCount,
    String? coverUrl,
  }) async {
    final existing = await findSeriesByName(name, subcategory);
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
      if (updated != existing) await updateSeries(updated);
      return updated;
    }
    return createSeries(
      name: name,
      subcategory: subcategory,
      expectedVolumeCount: expectedVolumeCount,
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
  }) async {
    final parsed = BookTitleParser.parse(title);
    if (!parsed.hasSeries) return null;

    var total = estimatedTotalVolumes;
    final volCeil = parsed.volumeNumber?.ceil() ?? 0;
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

    final series = await findOrCreateSeries(
      name: parsed.seriesName!,
      subcategory: subcategory,
      expectedVolumeCount: total,
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
      final coverUrl = await OpenLibraryService.lookupVolumeCover(
        series.name,
        n.toDouble(),
        series.subcategory,
      );
      if (coverUrl != null && coverUrl.isNotEmpty) {
        await setVolumeCoverUrl(vol.id, coverUrl);
      }
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
}
