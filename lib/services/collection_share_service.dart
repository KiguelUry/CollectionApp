import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/collection_item_filters.dart';
import '../utils/collection_item_scope.dart';
import 'collection_export_service.dart';

/// Résumé lisible (texte / HTML) pour partager hors de l'app.
class CollectionShareService {
  final _client = Supabase.instance.client;

  Future<List<CollectionItem>> _fetchItems() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return [];

    final rows = await CollectionItemScope.personal(
      _client
          .from('collection_items')
          .select(
            'id, title, category, quantity, rating, is_wishlist, is_for_sale, '
            'is_sold',
          )
          .order('category')
          .order('title'),
      userId: userId,
    );

    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<String> _username() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 'Ma collection';
    final row = await _client
        .from('profiles')
        .select('username')
        .eq('id', uid)
        .maybeSingle();
    return (row?['username'] as String?) ?? 'Ma collection';
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  String _itemLine(CollectionItem item) {
    final parts = <String>[item.title];
    if (item.quantity > 1) parts.add('×${item.quantity}');
    if (item.rating != null) {
      parts.add('★ ${item.rating!.toStringAsFixed(1)}');
    }
    return '• ${parts.join(' · ')}';
  }

  Future<String> buildReadableText() async {
    final name = await _username();
    final items = await _fetchItems();
    final now = DateTime.now();
    final owned = items.where(isActiveCollectionItem).toList();
    final wishlist = items.where((i) => i.isWishlist).toList();

    final buf = StringBuffer();
    buf.writeln('Collection de $name');
    buf.writeln('Liste du ${_formatDate(now)} — Collection Famille');
    buf.writeln('');

    if (owned.isEmpty) {
      buf.writeln('(Aucun objet dans la collection pour l\'instant.)');
    } else {
      buf.writeln('CE QUE J\'AI (${owned.length} objet${owned.length > 1 ? 's' : ''})');
      buf.writeln('');
      for (final cat in CollectionCategory.values) {
        final section =
            owned.where((i) => i.category == cat).toList()..sort(
                  (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
                );
        if (section.isEmpty) continue;
        buf.writeln('— ${cat.label} (${section.length}) —');
        for (final item in section) {
          buf.writeln(_itemLine(item));
        }
        buf.writeln('');
      }
    }

    if (wishlist.isNotEmpty) {
      buf.writeln('WISHLIST — ce que je cherche (${wishlist.length})');
      buf.writeln('');
      for (final cat in CollectionCategory.values) {
        final section =
            wishlist.where((i) => i.category == cat).toList()..sort(
                  (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
                );
        if (section.isEmpty) continue;
        buf.writeln('— ${cat.label} (${section.length}) —');
        for (final item in section) {
          buf.writeln(_itemLine(item));
        }
        buf.writeln('');
      }
    }

    buf.writeln('—');
    buf.writeln(
      'Partagé depuis Collection Famille. '
      'Pour voir la collection en direct dans l\'app, ajoute-moi en ami.',
    );
    return buf.toString();
  }

  Future<String> buildHtml() async {
    final name = await _username();
    final items = await _fetchItems();
    final owned = items.where(isActiveCollectionItem).toList();
    final wishlist = items.where((i) => i.isWishlist).toList();
    final date = _formatDate(DateTime.now());

    String sectionHtml(String title, List<CollectionItem> sectionItems) {
      if (sectionItems.isEmpty) return '';
      final blocks = StringBuffer();
      for (final cat in CollectionCategory.values) {
        final section = sectionItems.where((i) => i.category == cat).toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
        if (section.isEmpty) continue;
        blocks.writeln('<h3>${_escape(cat.label)} <span class="count">(${section.length})</span></h3>');
        blocks.writeln('<ul>');
        for (final item in section) {
          var label = _escape(item.title);
          if (item.quantity > 1) label += ' <span class="meta">×${item.quantity}</span>';
          if (item.rating != null) {
            label += ' <span class="meta">★ ${item.rating!.toStringAsFixed(1)}</span>';
          }
          blocks.writeln('<li>$label</li>');
        }
        blocks.writeln('</ul>');
      }
      return '<section><h2>$title</h2>$blocks</section>';
    }

    final ownedBlock = owned.isEmpty
        ? '<p class="empty">Aucun objet pour l\'instant.</p>'
        : sectionHtml(
            'Ce que j\'ai (${owned.length} objet${owned.length > 1 ? 's' : ''})',
            owned,
          );
    final wishBlock = wishlist.isEmpty
        ? ''
        : sectionHtml(
            'Wishlist — ce que je cherche (${wishlist.length})',
            wishlist,
          );

    return '''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Collection de ${_escape(name)}</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 2rem auto; padding: 0 1rem; color: #1a1a1a; line-height: 1.5; }
    h1 { color: #512DA8; font-size: 1.5rem; margin-bottom: 0.25rem; }
    .date { color: #666; font-size: 0.9rem; margin-bottom: 1.5rem; }
    h2 { font-size: 1.1rem; border-bottom: 2px solid #E8E0F5; padding-bottom: 0.35rem; margin-top: 1.5rem; }
    h3 { font-size: 0.95rem; color: #512DA8; margin: 1rem 0 0.35rem; }
    .count { font-weight: normal; color: #888; }
    ul { margin: 0 0 0.5rem; padding-left: 1.25rem; }
    li { margin: 0.2rem 0; }
    .meta { color: #666; font-size: 0.9em; }
    .empty { color: #888; font-style: italic; }
    footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #eee; font-size: 0.8rem; color: #888; }
  </style>
</head>
<body>
  <h1>Collection de ${_escape(name)}</h1>
  <p class="date">Liste du $date — Collection Famille</p>
  $ownedBlock
  $wishBlock
  <footer>
    Export Collection Famille. Pour la version interactive dans l'app, ajoute-moi en ami.
  </footer>
</body>
</html>''';
  }

  String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  Future<ShareExportResult> shareText() async {
    final text = await buildReadableText();
    return _shareString(
      content: text,
      subject: 'Ma collection',
      fileName: 'ma_collection.txt',
      mimeType: 'text/plain',
    );
  }

  Future<ShareExportResult> shareHtml() async {
    final html = await buildHtml();
    return CollectionExportService().shareStringAsFile(
      content: html,
      fileName: 'ma_collection.html',
      mimeType: 'text/html',
      subject: 'Ma collection',
      shareText: 'Ma collection (page HTML lisible dans le navigateur).',
    );
  }

  Future<ShareExportResult> copyTextToClipboard() async {
    final text = await buildReadableText();
    await Clipboard.setData(ClipboardData(text: text));
    return const ShareExportResult(
      kind: ShareExportKind.copiedToClipboard,
      message: 'Résumé copié dans le presse-papiers',
    );
  }

  Future<ShareExportResult> _shareString({
    required String content,
    required String subject,
    required String fileName,
    required String mimeType,
  }) {
    return CollectionExportService().shareStringAsFile(
      content: content,
      fileName: fileName,
      mimeType: mimeType,
      subject: subject,
      shareText: content.length > 8000 ? subject : content,
    );
  }
}
