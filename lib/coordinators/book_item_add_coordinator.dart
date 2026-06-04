import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/book_subcategory.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../screens/book_series_detail_screen.dart';
import '../services/book_series_service.dart';
import '../services/profile_service.dart';
import '../services/book_catalog_service.dart';
import '../services/open_library_service.dart';
import '../utils/book_title_parser.dart';
import '../utils/collection_item_scope.dart';
import '../widgets/add_item_manual_dialog.dart';
import '../widgets/add_item_options_dialog.dart';
import '../widgets/book_search_dialog.dart' show showBookSearch;
import '../widgets/book_subcategory_picker.dart';
import '../widgets/add_volume_to_series_sheet.dart';
import '../widgets/isbn_scan_sheet.dart';
import '../widgets/series_link_confirm_dialog.dart';
import '../widgets/volume_number_dialog.dart';

/// Flux d'ajout de livres partagé (hub livres, détail série, etc.).
class BookItemAddCoordinator {
  BookItemAddCoordinator(this.context);

  final BuildContext context;
  final _seriesService = BookSeriesService();

  Future<void> openSearch({BookSubcategory? subcategory}) async {
    await showBookSearch(
      context,
      initialSub: subcategory ?? BookSubcategory.manga,
      onBookSelected: (book, sub) {
        _prepareAdd(
          title: book['title']!,
          imageUrl: book['image_url']!.isEmpty ? null : book['image_url'],
          subcategory: subcategory ?? sub,
          metadata: BookCatalogService.metadataFromLookup(book),
        );
      },
    );
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
    final parsed = _resolveParsed(title, metadata);
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
                Flexible(child: Text('Analyse de la série…')),
              ],
            ),
          ),
        ),
      );

      final estimated = await OpenLibraryService.estimateSeriesVolumeCount(
        parsed.seriesName!,
        subcategory,
      );

      if (!context.mounted) return;
      Navigator.pop(context);

      final link = await showSeriesLinkConfirmDialog(
        context,
        parsed: parsed,
        estimatedVolumeCount: estimated,
      );
      if (link == null || !context.mounted) return;

      if (link) {
        final resolved = await _seriesService.resolveSeriesFromTitle(
          title: title,
          subcategory: subcategory,
          estimatedTotalVolumes: estimated,
        );
        if (resolved != null) {
          seriesId = resolved.seriesId;
          volumeId = resolved.volumeId;
          finalTitle = resolved.itemTitle;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            await _seriesService.ensureSeriesCoverFromItem(
              seriesId: resolved.seriesId,
              imageUrl: imageUrl,
            );
          }
        }
      }
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

      var dupQuery = client
          .from('collection_items')
          .select('id, quantity')
          .eq('category', 'book')
          .eq('title', title.trim());

      if (options.groupId != null) {
        dupQuery = dupQuery.eq('group_id', options.groupId!);
      } else {
        dupQuery = dupQuery
            .filter('group_id', 'is', null)
            .or(CollectionItemScope.personalOrFilter(userId));
      }

      final existing = await dupQuery.maybeSingle();
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
