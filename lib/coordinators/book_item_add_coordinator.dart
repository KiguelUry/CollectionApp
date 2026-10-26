import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/book_subcategory.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../screens/book_series_detail_screen.dart';
import '../services/book_series_service.dart';
import '../services/books_collection_cache.dart';
import '../services/collection_refresh.dart';
import '../services/profile_service.dart';
import '../services/book_catalog_service.dart';
import '../services/open_library_service.dart';
import '../utils/book_series_normalizer.dart';
import '../utils/book_title_parser.dart';
import '../utils/wishlist_promote.dart';
import '../widgets/add_item_manual_dialog.dart';
import '../widgets/add_item_options_dialog.dart';
import '../widgets/book_owned_range_dialog.dart';
import '../widgets/book_search_dialog.dart' show showBookSearch;
import '../widgets/book_subcategory_picker.dart';
import '../widgets/add_volume_to_series_sheet.dart';
import '../widgets/isbn_scan_sheet.dart';
import '../services/book_intelligence_service.dart';
import '../widgets/volume_number_dialog.dart';

/// Flux d'ajout de livres partagé (hub livres, détail série, etc.).
class BookItemAddCoordinator {
  BookItemAddCoordinator(this.context);

  final BuildContext context;
  final _seriesService = BookSeriesService();

  Future<void> openSearch({
    BookSubcategory? subcategory,
    String? initialQuery,
  }) async {
    await showBookSearch(
      context,
      initialSub: subcategory, // null = Tous
      initialQuery: initialQuery,
      onBookSelected: (book, sub) {
        // Toujours la catégorie détectée (Manga/BD/…), jamais la pilule seule.
        _prepareAdd(
          title: book['title']!,
          imageUrl: book['image_url']!.isEmpty ? null : book['image_url'],
          subcategory: sub,
          metadata: BookCatalogService.metadataFromLookup(book),
        );
      },
      onAddSeries: (name, sub, {volumeCount, coversByVolume, author}) async {
        await _addSeriesFromSearch(
          name: name,
          subcategory: subcategory ?? sub,
          volumeCount: volumeCount,
          coversByVolume: coversByVolume,
          coverUrl: coversByVolume?[1],
          author: author,
        );
      },
    );
  }

  /// Ajout série depuis la recherche : popup possession immédiat, reste sur la page.
  Future<void> _addSeriesFromSearch({
    required String name,
    required BookSubcategory subcategory,
    int? volumeCount,
    Map<int, String>? coversByVolume,
    String? coverUrl,
    String? author,
  }) async {
    final preferred =
        BookSeriesNormalizer.preferredSubcategory(name) ?? subcategory;
    final total = volumeCount ??
        BookSeriesNormalizer.expectedCount(name, preferred) ??
        1;

    // Popup 0 ms — aucun réseau avant.
    if (!context.mounted) return;
    final range = await showBookOwnedRangeDialog(
      context,
      seriesName: name,
      totalVolumes: total,
    );
    if (range == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Flexible(child: Text('Ajout de la série…')),
            ],
          ),
        ),
      ),
    );

    try {
      // Upsert : crée la série si absente (jamais « série introuvable »).
      final cleanName = BookSeriesNormalizer.displaySeriesName(name);
      var series = await _seriesService.findOrCreateSeries(
        name: cleanName,
        subcategory: preferred,
        expectedVolumeCount: total,
        coverUrl: coverUrl ?? coversByVolume?[1],
        author: author,
      );
      await _seriesService.ensureVolumeSlots(series.id, total);

      final seriesCover = coverUrl ?? coversByVolume?[1];
      if (seriesCover != null && seriesCover.isNotEmpty) {
        await _seriesService.ensureSeriesCoverFromItem(
          seriesId: series.id,
          imageUrl: seriesCover,
        );
      }
      if (coversByVolume != null && coversByVolume.isNotEmpty) {
        await _seriesService.applyVolumeCoversFromMap(
          seriesId: series.id,
          coverByVolume: coversByVolume,
        );
      }

      series = (await _seriesService.fetchSeriesById(series.id)) ?? series;
      if (range.choice == BookOwnedRangeChoice.all) {
        await _seriesService.markVolumesOwned(
          series: series,
          fromVolume: 1,
          toVolume: total,
        );
      } else if (range.choice == BookOwnedRangeChoice.range &&
          range.from != null &&
          range.to != null) {
        await _seriesService.markVolumesOwned(
          series: series,
          fromVolume: range.from!,
          toVolume: range.to!,
        );
      }

      final volumes = await _seriesService.fetchVolumes(series.id);
      final items = await _seriesService.fetchSeriesItems(series.id);
      final stats = _seriesService.computeStats(
        series: series,
        volumes: volumes,
        items: items,
      );
      BooksCollectionCache.instance.updateSeries(
        seriesId: series.id,
        series: series,
        volumes: volumes,
        items: items,
        stats: stats,
      );
      // Hydrate note communauté en arrière-plan.
      // ignore: unawaited_futures
      _seriesService.hydrateCommunityRating(series);
      CollectionRefresh.instance.bump();

      if (context.mounted) {
        Navigator.pop(context); // loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('« $name » ajoutée à ta collection')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  Future<void> scanIsbn() async {
    final isbn = await showIsbnScanSheet(context);
    if (isbn == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Flexible(child: Text('Recherche du livre…')),
            ],
          ),
        ),
      ),
    );

    final book = await BookCatalogService.lookupByIsbn(isbn);
    if (!context.mounted) return;
    Navigator.pop(context);

    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ISBN introuvable')),
      );
      return;
    }

    final suggested = book['subcategory_hint'] != null
        ? BookSubcategory.fromDbValue(book['subcategory_hint'])
        : BookSubcategory.other;

    final sub = await showBookSubcategoryPicker(context, suggested: suggested);
    if (!context.mounted || sub == null) return;

    await _prepareAdd(
      title: book['title']!,
      imageUrl: book['image_url']?.isNotEmpty == true ? book['image_url'] : null,
      subcategory: sub,
      metadata: BookCatalogService.metadataFromLookup(book),
    );
  }

  Future<void> openManual({BookSubcategory? subcategory}) async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AddItemManualDialog(
        categoryLabel: CollectionCategory.book.label,
        category: CollectionCategory.book,
      ),
    );
    if (draft == null || !context.mounted) return;
    final sub = BookSubcategory.fromDbValue(
      draft['subcategory'] as String? ?? subcategory?.dbValue,
    );
    await _prepareAdd(
      title: draft['title'] as String,
      imageUrl: draft['image_url'] as String?,
      subcategory: sub,
      metadata: draft['metadata'] as Map<String, dynamic>?,
    );
  }

  Future<void> addToVolume({
    required String seriesId,
    required String volumeId,
    required String seriesName,
    required BookSubcategory subcategory,
    required double volumeNumber,
    int? expectedVolumeCount,
  }) async {
    final choice = await showAddVolumeToSeriesSheet(context);
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case AddVolumeToSeriesChoice.search:
        await _addToVolumeViaSearch(
          seriesId: seriesId,
          seriesName: seriesName,
          subcategory: subcategory,
          volumeNumber: volumeNumber,
          expectedVolumeCount: expectedVolumeCount,
        );
      case AddVolumeToSeriesChoice.isbn:
        await _addToVolumeViaIsbn(
          seriesId: seriesId,
          seriesName: seriesName,
          subcategory: subcategory,
          volumeNumber: volumeNumber,
          expectedVolumeCount: expectedVolumeCount,
        );
      case AddVolumeToSeriesChoice.manual:
        await _addToVolumeManual(
          seriesId: seriesId,
          seriesName: seriesName,
          subcategory: subcategory,
          volumeId: volumeId,
          volumeNumber: volumeNumber,
        );
    }
  }

  Future<void> addVolumeFromCatalog({
    required String seriesId,
    required String seriesName,
    required BookSubcategory subcategory,
    int? expectedVolumeCount,
  }) async {
    await _addToVolumeViaSearch(
      seriesId: seriesId,
      seriesName: seriesName,
      subcategory: subcategory,
      volumeNumber: null,
      expectedVolumeCount: expectedVolumeCount,
    );
  }

  Future<void> _addToVolumeViaSearch({
    required String seriesId,
    required String seriesName,
    required BookSubcategory subcategory,
    required double? volumeNumber,
    int? expectedVolumeCount,
  }) async {
    if (!context.mounted) return;
    await showBookSearch(
      context,
      initialSub: subcategory,
      onBookSelected: (book, _) async {
        if (!context.mounted) return;
        await _finishVolumeAddFromBook(
          seriesId: seriesId,
          seriesName: seriesName,
          subcategory: subcategory,
          slotVolumeNumber: volumeNumber,
          expectedVolumeCount: expectedVolumeCount,
          title: book['title']!,
          imageUrl: book['image_url']!.isEmpty ? null : book['image_url'],
          metadata: BookCatalogService.metadataFromLookup(book),
        );
      },
    );
  }

  Future<void> _addToVolumeViaIsbn({
    required String seriesId,
    required String seriesName,
    required BookSubcategory subcategory,
    required double? volumeNumber,
    int? expectedVolumeCount,
  }) async {
    final isbn = await showIsbnScanSheet(context);
    if (isbn == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Flexible(child: Text('Recherche du livre…')),
            ],
          ),
        ),
      ),
    );

    final book = await BookCatalogService.lookupByIsbn(isbn);
    if (!context.mounted) return;
    Navigator.pop(context);

    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ISBN introuvable')),
      );
      return;
    }

    await _finishVolumeAddFromBook(
      seriesId: seriesId,
      seriesName: seriesName,
      subcategory: subcategory,
      slotVolumeNumber: volumeNumber,
      expectedVolumeCount: expectedVolumeCount,
      title: book['title']!,
      imageUrl: book['image_url']?.isNotEmpty == true ? book['image_url'] : null,
      metadata: BookCatalogService.metadataFromLookup(book),
    );
  }

  Future<void> _addToVolumeManual({
    required String seriesId,
    required String seriesName,
    required BookSubcategory subcategory,
    required String volumeId,
    required double volumeNumber,
  }) async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AddItemManualDialog(
        categoryLabel:
            'Tome ${volumeNumber == volumeNumber.roundToDouble() ? volumeNumber.toInt() : volumeNumber}',
        category: CollectionCategory.book,
      ),
    );
    if (draft == null || !context.mounted) return;
    await _prepareAddToVolume(
      seriesId: seriesId,
      seriesName: seriesName,
      volumeNumber: volumeNumber,
      title: draft['title'] as String,
      imageUrl: draft['image_url'] as String?,
      subcategory: subcategory,
      metadata: draft['metadata'] as Map<String, dynamic>?,
    );
  }

  Future<void> _finishVolumeAddFromBook({
    required String seriesId,
    required String seriesName,
    required BookSubcategory subcategory,
    required double? slotVolumeNumber,
    int? expectedVolumeCount,
    required String title,
    String? imageUrl,
    Map<String, dynamic>? metadata,
  }) async {
    final parsed = BookTitleParser.parse(title);
    double? volNum;

    if (parsed.hasVolume && parsed.volumeNumber != null) {
      volNum = parsed.volumeNumber;
    } else {
      volNum = slotVolumeNumber;
    }

    volNum ??= await showVolumeNumberDialog(
        context,
        seriesName: seriesName,
        maxHint: expectedVolumeCount,
      );

    if (!context.mounted || volNum == null) return;

    await _prepareAddToVolume(
      seriesId: seriesId,
      seriesName: seriesName,
      volumeNumber: volNum,
      title: title,
      imageUrl: imageUrl,
      subcategory: subcategory,
      metadata: metadata,
    );
  }

  Future<void> _prepareAddToVolume({
    required String seriesId,
    required String seriesName,
    required double volumeNumber,
    required String title,
    String? imageUrl,
    required BookSubcategory subcategory,
    Map<String, dynamic>? metadata,
  }) async {
    final cap = volumeNumber.ceil();
    final series = await _seriesService.fetchSeriesById(seriesId);
    if (series != null) {
      final expected = series.expectedVolumeCount ?? 0;
      if (cap > expected) {
        await _seriesService.ensureVolumeSlots(seriesId, cap);
        await _seriesService.updateSeries(
          series.copyWith(expectedVolumeCount: cap),
        );
      }
    }

    final vol = await _seriesService.getOrCreateVolume(seriesId, volumeNumber);
    final parsed = BookTitleParser.parse(title);
    var finalTitle = parsed.hasSeries ? parsed.itemTitle : title;
    if (finalTitle.trim().isEmpty) {
      finalTitle = '$seriesName - Tome ${vol.displayNumber}';
    }

    if (imageUrl != null && imageUrl.isNotEmpty) {
      await _seriesService.setVolumeCoverUrl(vol.id, imageUrl);
      await _seriesService.ensureSeriesCoverFromItem(
        seriesId: seriesId,
        imageUrl: imageUrl,
      );
    }

    if (!context.mounted) return;
    await _showOptions(
      title: finalTitle,
      imageUrl: imageUrl,
      subcategory: subcategory,
      metadata: metadata,
      seriesId: seriesId,
      volumeId: vol.id,
    );
  }

  ParsedBookTitle _resolveParsed(String title, Map<String, dynamic>? metadata) {
    var parsed = BookTitleParser.parse(title);
    if (!parsed.hasSeries && metadata != null) {
      final seriesName = metadata['series_title']?.toString().trim();
      final volRaw = metadata['series_volume']?.toString();
      final vol = double.tryParse(volRaw?.replaceAll(',', '.') ?? '');
      if (seriesName != null &&
          seriesName.isNotEmpty &&
          vol != null &&
          vol > 0) {
        parsed = ParsedBookTitle(
          rawTitle: title,
          seriesName: seriesName,
          volumeNumber: vol,
        );
      }
    }
    return parsed;
  }

  Future<void> _prepareAdd({
    required String title,
    String? imageUrl,
    required BookSubcategory subcategory,
    Map<String, dynamic>? metadata,
  }) async {
    var parsed = _resolveParsed(title, metadata);
    // Titre nu d'une série connue (ex. « Thorgal », « Naruto ») → dossier série.
    if (!parsed.hasSeries) {
      final known = BookSeriesNormalizer.expectedCount(title.trim(), subcategory);
      final metaSeries = metadata?['series_title']?.toString().trim();
      if (known != null && known > 1) {
        parsed = ParsedBookTitle(
          rawTitle: title,
          seriesName: title.trim(),
        );
      } else if (metaSeries != null && metaSeries.length >= 2) {
        final metaKnown =
            BookSeriesNormalizer.expectedCount(metaSeries, subcategory);
        if (metaKnown != null && metaKnown > 1) {
          parsed = ParsedBookTitle(
            rawTitle: title,
            seriesName: metaSeries,
          );
        }
      }
    }

    String? seriesId;
    String? volumeId;
    var finalTitle = title;

    if (parsed.hasSeries && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Flexible(child: Text('Préparation de la série…')),
              ],
            ),
          ),
        ),
      );

      final enriched = BookIntelligenceService.enrichSingle(
        {
          'title': title,
          if (metadata?['series_title'] != null)
            'series_title': metadata!['series_title']!.toString(),
          if (metadata?['author'] != null)
            'author': metadata!['author']!.toString(),
        },
        subcategory,
      );
      var estimated = int.tryParse(
            metadata?['estimated_volumes']?.toString() ?? '',
          ) ??
          enriched.estimatedTotalVolumes ??
          BookSeriesNormalizer.expectedCount(parsed.seriesName!, subcategory);
      estimated ??= await OpenLibraryService.estimateSeriesVolumeCount(
        parsed.seriesName!,
        subcategory,
      );

      if (!context.mounted) return;
      Navigator.pop(context);

      final authorFromMeta = metadata?['author']?.toString();
      final resolved = await _seriesService.resolveSeriesFromTitle(
        title: parsed.hasVolume ? title : parsed.seriesName!,
        subcategory: subcategory,
        estimatedTotalVolumes: estimated,
        coverUrl: imageUrl,
        author: authorFromMeta,
      );
      if (resolved != null) {
        seriesId = resolved.seriesId;
        volumeId = parsed.hasVolume ? resolved.volumeId : null;
        finalTitle = parsed.hasVolume ? resolved.itemTitle : parsed.seriesName!;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          await _seriesService.ensureSeriesCoverFromItem(
            seriesId: resolved.seriesId,
            imageUrl: imageUrl,
          );
        }
        if (authorFromMeta != null && authorFromMeta.trim().isNotEmpty) {
          final s = await _seriesService.fetchSeriesById(resolved.seriesId);
          if (s != null) {
            await _seriesService.ensureSeriesAuthor(s, authorFromMeta);
          }
        }
        // Couvertures par tome découvertes à la recherche.
        final coversRaw = metadata?['volume_covers_json']?.toString();
        if (coversRaw != null && coversRaw.isNotEmpty) {
          final map = <int, String>{};
          for (final part in coversRaw.split('|')) {
            final i = part.indexOf(':');
            if (i <= 0) continue;
            final n = int.tryParse(part.substring(0, i));
            final url = part.substring(i + 1);
            if (n != null && n > 0 && url.isNotEmpty) map[n] = url;
          }
          if (map.isNotEmpty) {
            await _seriesService.applyVolumeCoversFromMap(
              seriesId: resolved.seriesId,
              coverByVolume: map,
            );
          }
        }

        // Ajout série entière (sans tome précis) → plage possédée + ouverture dossier.
        if (!parsed.hasVolume && context.mounted) {
          final series = await _seriesService.fetchSeriesById(resolved.seriesId);
          final total = series?.expectedVolumeCount ?? estimated ?? 1;
          final range = await showBookOwnedRangeDialog(
            context,
            seriesName: parsed.seriesName!,
            totalVolumes: total,
          );
          if (range == null || !context.mounted) return;
          if (series != null) {
            if (range.choice == BookOwnedRangeChoice.all) {
              await _seriesService.markVolumesOwned(
                series: series,
                fromVolume: 1,
                toVolume: total,
              );
            } else if (range.choice == BookOwnedRangeChoice.range &&
                range.from != null &&
                range.to != null) {
              await _seriesService.markVolumesOwned(
                series: series,
                fromVolume: range.from!,
                toVolume: range.to!,
              );
            }
          }
          if (!context.mounted) return;
          CollectionRefresh.instance.bump();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookSeriesDetailScreen(seriesId: resolved.seriesId),
            ),
          );
          CollectionRefresh.instance.bump();
          return;
        }
      }
    } else if (context.mounted) {
      final resolved = await _seriesService.resolveStandaloneBook(
        bookTitle: title,
        subcategory: subcategory,
        coverUrl: imageUrl,
      );
      seriesId = resolved.seriesId;
      volumeId = resolved.volumeId;
      finalTitle = title;
    }

    if (!context.mounted) return;
    await _showOptions(
      title: finalTitle,
      imageUrl: imageUrl,
      subcategory: subcategory,
      metadata: metadata,
      seriesId: seriesId,
      volumeId: volumeId,
    );
  }

  Future<void> _showOptions({
    required String title,
    String? imageUrl,
    required BookSubcategory subcategory,
    Map<String, dynamic>? metadata,
    String? seriesId,
    String? volumeId,
  }) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AddItemOptionsDialog(
        itemTitle: title,
        itemImageUrl: imageUrl,
        bookCover: true,
        onConfirm: (options) => _save(
          dialogContext: dialogContext,
          title: title,
          options: options,
          imageUrl: imageUrl,
          subcategory: subcategory.dbValue,
          metadata: metadata,
          seriesId: seriesId,
          volumeId: volumeId,
        ),
      ),
    );
  }

  Future<void> _save({
    required BuildContext dialogContext,
    required String title,
    required AddItemOptions options,
    String? imageUrl,
    String? subcategory,
    Map<String, dynamic>? metadata,
    String? seriesId,
    String? volumeId,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    try {
      await ProfileService().ensureCurrentUserProfile();

      final existing = await findDuplicateRow(
        title: title,
        categoryDb: 'book',
        isWishlist: options.isWishlist,
        subcategory: subcategory,
        groupId: options.groupId,
      );
      var message = '« $title » ajouté';
      if (seriesId != null) {
        message = '« $title » ajouté à la série';
      }

      if (existing != null) {
        final newQty =
            ((existing['quantity'] as int?) ?? 1) + options.quantity;
        await client.from('collection_items').update({
          'quantity': newQty,
          if (seriesId != null) 'series_id': seriesId,
          if (volumeId != null) 'volume_id': volumeId,
        }).eq('id', existing['id']);
        message = 'Quantité mise à jour ($newQty)';
      } else {
        final item = CollectionItem(
          id: '',
          title: title.trim(),
          category: CollectionCategory.book,
          subcategory: subcategory,
          metadata: metadata,
          imageUrl: imageUrl,
          isWishlist: options.isWishlist,
          quantity: options.isWishlist ? 1 : options.quantity,
          locationId: options.locationId,
          groupId: options.groupId,
          seriesId: seriesId,
          volumeId: volumeId,
        );
        await client.from('collection_items').insert(
              item.toInsertJson(
                isWishlist: options.isWishlist,
                locationUserId: options.isWishlist
                    ? null
                    : (options.locationUserId ?? userId),
                addedBy: userId,
              ),
            );
        if (options.isWishlist) message = 'Ajouté à la wishlist';
      }

      if (volumeId != null && imageUrl != null && imageUrl.isNotEmpty) {
        await _seriesService.setVolumeCoverUrl(volumeId, imageUrl);
      }
      if (seriesId != null && imageUrl != null && imageUrl.isNotEmpty) {
        await _seriesService.ensureSeriesCoverFromItem(
          seriesId: seriesId,
          imageUrl: imageUrl,
        );
      }

      CollectionRefresh.instance.bump();
      if (context.mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        if (seriesId != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => BookSeriesDetailScreen(seriesId: seriesId),
            ),
          );
          CollectionRefresh.instance.bump();
        }
      }
    } on PostgrestException catch (e) {
      if (context.mounted) {
        final msg = ProfileService.isMissingProfileFk(e)
            ? ProfileService.missingProfileUserMessage()
            : 'Impossible d\'ajouter : $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      rethrow;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ajouter : $e')),
        );
      }
      rethrow;
    }
  }
}
