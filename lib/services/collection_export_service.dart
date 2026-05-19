import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_item_scope.dart';

enum ShareExportKind { shared, savedToFile, copiedToClipboard }

class ShareExportResult {
  final ShareExportKind kind;
  final String message;
  final String? savedPath;

  const ShareExportResult({
    required this.kind,
    required this.message,
    this.savedPath,
  });
}

/// Export CSV pour assurance / inventaire.
class CollectionExportService {
  final _client = Supabase.instance.client;

  Future<String> buildCsv() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) throw Exception('Non connecté');

    final rows = await CollectionItemScope.personal(
      _client.from('collection_items').select(
        'id, title, category, subcategory, quantity, purchase_price, rating, '
        'review, condition, is_wishlist, is_for_sale, is_sold, '
        'locations(label)',
      ),
      userId: userId,
    ).order('category').order('title');

    final buffer = StringBuffer();
    buffer.writeln(
      'titre;catégorie;sous-type;quantité;prix_achat_eur;note;état;'
      'wishlist;à_vendre;vendu;emplacement;avis',
    );

    for (final row in rows as List) {
      final item = CollectionItem.fromJson(Map<String, dynamic>.from(row));
      final loc = row['locations'];
      final locLabel = loc is Map ? loc['label'] as String? : null;

      buffer.writeln([
        _cell(item.title),
        _cell(item.category.label),
        _cell(item.subcategory ?? ''),
        '${item.quantity}',
        item.purchasePrice?.toStringAsFixed(2) ?? '',
        item.rating?.toStringAsFixed(1) ?? '',
        _cell(item.condition ?? ''),
        item.isWishlist ? 'oui' : 'non',
        item.isForSale ? 'oui' : 'non',
        item.isSold ? 'oui' : 'non',
        _cell(locLabel ?? ''),
        _cell(item.review ?? ''),
      ].join(';'));
    }

    buffer.writeln();
    buffer.writeln(
      '# Valeur indicative : somme des prix d\'achat renseignés (objets actifs).',
    );

    var total = 0.0;
    var priced = 0;
    for (final row in rows) {
      if (row['is_wishlist'] == true ||
          row['is_sold'] == true ||
          row['is_for_sale'] == true) {
        continue;
      }
      final price = row['purchase_price'];
      if (price == null) continue;
      final unit = price is num ? price.toDouble() : double.tryParse('$price');
      if (unit == null) continue;
      final qty = (row['quantity'] as int?) ?? 1;
      priced++;
      total += unit * qty;
    }
    buffer.writeln('# Objets avec prix;$priced');
    buffer.writeln('# Total achat (€);${total.toStringAsFixed(2)}');

    return buffer.toString();
  }

  Future<ShareExportResult> shareCsv() async {
    final csv = await buildCsv();
    final stamp = DateTime.now().toIso8601String().split('T').first;
    return shareStringAsFile(
      content: csv,
      fileName: 'ma_collection_$stamp.csv',
      mimeType: 'text/csv',
      subject: 'Export collection',
      shareText: 'Export de ma collection (valeurs indicatives).',
    );
  }

  Future<ShareExportResult> shareStringAsFile({
    required String content,
    required String fileName,
    required String mimeType,
    required String subject,
    required String shareText,
  }) async {
    if (kIsWeb) {
      await Share.share(content, subject: subject);
      return const ShareExportResult(
        kind: ShareExportKind.shared,
        message: 'Partage lancé',
      );
    }

    final desktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (desktop) {
      final saved = await _saveWithDialog(fileName, content);
      if (saved != null) {
        return ShareExportResult(
          kind: ShareExportKind.savedToFile,
          message: 'Fichier enregistré :\n$saved',
          savedPath: saved,
        );
      }
    }

    final saved = await _writeToUserFolder(fileName, content);

    try {
      await Share.shareXFiles(
        [XFile(saved, mimeType: mimeType, name: fileName)],
        subject: subject,
        text: shareText,
      );
      return const ShareExportResult(
        kind: ShareExportKind.shared,
        message: 'Partage lancé',
      );
    } catch (_) {}

    try {
      final preview =
          content.length > 12000 ? '${content.substring(0, 12000)}…' : content;
      await Share.share(preview, subject: subject);
      return const ShareExportResult(
        kind: ShareExportKind.shared,
        message: 'Contenu partagé',
      );
    } catch (_) {}

    try {
      await Clipboard.setData(ClipboardData(text: content));
      return ShareExportResult(
        kind: ShareExportKind.savedToFile,
        message: 'Fichier dans Téléchargements et copié dans le presse-papiers :\n$saved',
        savedPath: saved,
      );
    } catch (_) {
      return ShareExportResult(
        kind: ShareExportKind.savedToFile,
        message: 'Fichier enregistré :\n$saved',
        savedPath: saved,
      );
    }
  }

  Future<String?> _saveWithDialog(String fileName, String content) async {
    try {
      final ext = fileName.contains('.') ? fileName.split('.').last : 'txt';
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
        ],
      );
      if (location == null) return null;

      final file = File(location.path);
      await file.writeAsString(content, flush: true);
      return location.path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _writeToUserFolder(String fileName, String content) async {
    final dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsString(content, flush: true);
    return path;
  }

  String _cell(String value) {
    final escaped = value.replaceAll('"', '""').replaceAll('\n', ' ');
    return '"$escaped"';
  }
}
