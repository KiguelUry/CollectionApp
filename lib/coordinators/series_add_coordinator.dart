import 'package:flutter/material.dart';

import '../models/book_series.dart';
import '../models/book_subcategory.dart';
import '../models/series_search_hit.dart';
import '../screens/book_series_detail_screen.dart';
import '../services/book_series_service.dart';
import '../services/open_library_service.dart';
import '../widgets/series_search_dialog.dart';

/// Création d'une série par recherche (ex. Thorgal) puis ouverture directe.
class SeriesAddCoordinator {
  SeriesAddCoordinator(this.context);

  final BuildContext context;
  final _service = BookSeriesService();

  Future<void> openSeriesSearch(BookSubcategory subcategory) async {
    final hit = await showSeriesSearchDialog(
      context,
      subcategory: subcategory,
    );
    if (hit == null || !context.mounted) return;

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
              Flexible(child: Text('Création de la série…')),
            ],
          ),
        ),
      ),
    );

    final series = await _createFromHit(hit, subcategory);

    if (!context.mounted) return;
    Navigator.pop(context);

    if (series == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de créer la série')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Série « ${series.name} » créée')),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => BookSeriesDetailScreen(seriesId: series.id),
      ),
    );
  }

  Future<BookSeries?> _createFromHit(
    SeriesSearchHit hit,
    BookSubcategory subcategory,
  ) async {
    var total = hit.estimatedVolumes;
    total ??= await OpenLibraryService.estimateSeriesVolumeCount(
      hit.name,
      subcategory,
    );

    return _service.findOrCreateSeries(
      name: hit.name,
      subcategory: subcategory,
      expectedVolumeCount: total,
      coverUrl: hit.coverUrl,
    );
  }
}
