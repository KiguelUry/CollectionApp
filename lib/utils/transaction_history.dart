import 'package:intl/intl.dart';

/// Entrée d'historique vente / échange (metadata.transaction_history).
class TransactionRecord {
  final String kind; // sold | traded
  final DateTime date;
  final double? salePrice;
  final String? tradedFor;

  const TransactionRecord({
    required this.kind,
    required this.date,
    this.salePrice,
    this.tradedFor,
  });

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    return TransactionRecord(
      kind: json['kind']?.toString() ?? 'sold',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      salePrice: _parseDouble(json['price']),
      tradedFor: json['received']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'date': date.toUtc().toIso8601String(),
        if (salePrice != null) 'price': salePrice,
        if (tradedFor != null && tradedFor!.trim().isNotEmpty)
          'received': tradedFor!.trim(),
      };

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }
}

List<TransactionRecord> parseTransactionHistory(Map<String, dynamic>? metadata) {
  final raw = metadata?['transaction_history'];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => TransactionRecord.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

int transactionCount(Map<String, dynamic>? metadata, String kind) =>
    parseTransactionHistory(metadata).where((r) => r.kind == kind).length;

Map<String, dynamic> metadataWithTransaction(
  Map<String, dynamic>? metadata,
  TransactionRecord record,
) {
  final meta = Map<String, dynamic>.from(metadata ?? {});
  final list = parseTransactionHistory(meta)
      .map((r) => r.toJson())
      .toList();
  list.add(record.toJson());
  meta['transaction_history'] = list;
  return meta;
}

String formatTransactionHistorySummary(Map<String, dynamic>? metadata) {
  final records = parseTransactionHistory(metadata);
  if (records.isEmpty) return '';

  final sold = records.where((r) => r.kind == 'sold').toList();
  final traded = records.where((r) => r.kind == 'traded').toList();
  final parts = <String>[];

  if (sold.isNotEmpty) {
    final prices = sold
        .where((r) => r.salePrice != null)
        .map((r) => r.salePrice!)
        .toList();
    if (prices.isNotEmpty) {
      final avg = prices.reduce((a, b) => a + b) / prices.length;
      parts.add(
        'Vendu ${sold.length} fois (moy. ${avg.toStringAsFixed(0)} €)',
      );
    } else {
      parts.add('Vendu ${sold.length} fois');
    }
  }

  if (traded.isNotEmpty) {
    parts.add('Échangé ${traded.length} fois');
  }

  return parts.join(' · ');
}

String formatTransactionRecordLine(TransactionRecord r) {
  final date = DateFormat('d MMM yyyy', 'fr_FR').format(r.date);
  if (r.kind == 'traded') {
    final against = r.tradedFor?.trim();
    return against != null && against.isNotEmpty
        ? '$date — Échangé contre $against'
        : '$date — Échangé';
  }
  final price = r.salePrice;
  return price != null
      ? '$date — Vendu ${price.toStringAsFixed(2)} €'
      : '$date — Vendu';
}
