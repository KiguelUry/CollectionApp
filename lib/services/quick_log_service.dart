import 'package:supabase_flutter/supabase_flutter.dart';

/// Journal Quick Log — sessions datées par l'utilisateur.
class QuickLogService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<QuickLogEntry>> fetchMyLogs({int limit = 40}) async {
    final id = _userId;
    if (id == null) return [];
    try {
      final rows = await _client
          .from('user_quick_logs')
          .select('*, collection_items(title, image_url, category)')
          .eq('user_id', id)
          .order('logged_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => QuickLogEntry.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addLog({
    required String note,
    String? itemId,
    DateTime? loggedAt,
  }) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');
    await _client.from('user_quick_logs').insert({
      'user_id': id,
      'item_id': itemId,
      'note': note.trim(),
      'logged_at': (loggedAt ?? DateTime.now()).toIso8601String(),
    });
  }

  Future<void> deleteLog(String logId) async {
    await _client.from('user_quick_logs').delete().eq('id', logId);
  }
}

class QuickLogEntry {
  final String id;
  final String note;
  final DateTime loggedAt;
  final String? itemId;
  final String? itemTitle;
  final String? itemImageUrl;
  final String? itemCategory;

  const QuickLogEntry({
    required this.id,
    required this.note,
    required this.loggedAt,
    this.itemId,
    this.itemTitle,
    this.itemImageUrl,
    this.itemCategory,
  });

  factory QuickLogEntry.fromJson(Map<String, dynamic> json) {
    final item = json['collection_items'];
    Map<String, dynamic>? itemMap;
    if (item is Map) itemMap = Map<String, dynamic>.from(item);

    return QuickLogEntry(
      id: json['id'] as String,
      note: json['note'] as String,
      loggedAt: DateTime.parse(json['logged_at'] as String),
      itemId: json['item_id'] as String?,
      itemTitle: itemMap?['title'] as String?,
      itemImageUrl: itemMap?['image_url'] as String?,
      itemCategory: itemMap?['category'] as String?,
    );
  }
}
