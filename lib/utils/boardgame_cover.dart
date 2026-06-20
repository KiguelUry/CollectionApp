import '../models/bgg_catalog_game.dart';
import '../services/bgg_service.dart';
import '../widgets/cover_preview_sheet.dart';
import 'package:flutter/material.dart';

/// URL à enregistrer en base : fiche BGG complète en priorité (comme HomeScreen).
String? boardgameStorageImageUrl({
  Map<String, dynamic>? details,
  String? catalogUrl,
}) {
  final fromDetails = details?['image_url']?.toString();
  if (fromDetails != null && fromDetails.isNotEmpty) return fromDetails;
  if (catalogUrl != null && catalogUrl.isNotEmpty) return catalogUrl;
  return null;
}

/// Résout la couverture HD via l'API thing BGG.
Future<String?> resolveBoardgameFullCoverUrl({
  required String bggId,
  String? fallback,
}) async {
  if (bggId.isEmpty) return fallback;
  final details = await BggService.getGameFullDetails(bggId);
  return boardgameStorageImageUrl(details: details, catalogUrl: fallback);
}

/// Aperçu plein écran avec image HD (long-press catalogue).
Future<void> showBoardgameCatalogCoverPreview(
  BuildContext context, {
  required BggCatalogGame game,
}) async {
  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Chargement de l\'image…'),
            ],
          ),
        ),
      ),
    ),
  );

  final url = await resolveBoardgameFullCoverUrl(
    bggId: game.bggId,
    fallback: game.imageUrl,
  );

  if (!context.mounted) return;
  Navigator.pop(context);

  if (url == null || url.isEmpty) return;

  await showCoverPreview(
    context,
    imageUrl: url,
    title: game.title,
    boxedCover: true,
  );
}
