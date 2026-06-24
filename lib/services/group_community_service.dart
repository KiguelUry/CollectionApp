import 'package:supabase_flutter/supabase_flutter.dart';

class GroupRuleEntry {
  final String id;
  final String groupId;
  final String itemId;
  final String authorId;
  final String title;
  final String body;
  final int voteCount;
  final DateTime? createdAt;
  final bool votedByMe;

  const GroupRuleEntry({
    required this.id,
    required this.groupId,
    required this.itemId,
    required this.authorId,
    required this.title,
    required this.body,
    required this.voteCount,
    this.createdAt,
    this.votedByMe = false,
  });

  factory GroupRuleEntry.fromJson(
    Map<String, dynamic> json, {
    bool votedByMe = false,
  }) {
    return GroupRuleEntry(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      itemId: json['item_id'] as String,
      authorId: json['author_id'] as String,
      title: json['title'] as String? ?? 'Variante',
      body: json['body'] as String? ?? '',
      voteCount: json['vote_count'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      votedByMe: votedByMe,
    );
  }
}

class GroupWantedPost {
  final String id;
  final String groupId;
  final String authorId;
  final String message;
  final String? itemId;
  final Map<String, dynamic> catalogPayload;
  final String? claimedBy;
  final DateTime? createdAt;
  final String? authorName;

  const GroupWantedPost({
    required this.id,
    required this.groupId,
    required this.authorId,
    required this.message,
    this.itemId,
    this.catalogPayload = const {},
    this.claimedBy,
    this.createdAt,
    this.authorName,
  });

  String? get imageUrl => catalogPayload['image_url']?.toString();
  String? get linkedTitle =>
      catalogPayload['title']?.toString() ?? catalogPayload['name']?.toString();

  factory GroupWantedPost.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'] as Map<String, dynamic>?;
    return GroupWantedPost(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      authorId: json['author_id'] as String,
      message: json['message'] as String? ?? '',
      itemId: json['item_id'] as String?,
      catalogPayload: Map<String, dynamic>.from(
        json['catalog_payload'] as Map? ?? const {},
      ),
      claimedBy: json['claimed_by'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      authorName: profiles?['username']?.toString(),
    );
  }
}

class GroupCommunityService {
  final _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  Future<List<GroupRuleEntry>> fetchRules({
    required String groupId,
    required String itemId,
  }) async {
    try {
      final rows = await _client
          .from('group_rule_entries')
          .select()
          .eq('group_id', groupId)
          .eq('item_id', itemId)
          .order('vote_count', ascending: false)
          .order('created_at', ascending: false);

      final votes = await _client
          .from('group_rule_votes')
          .select('rule_id')
          .eq('voter_id', _userId);

      final voted = (votes as List)
          .map((r) => r['rule_id'] as String)
          .toSet();

      return (rows as List)
          .map(
            (r) => GroupRuleEntry.fromJson(
              Map<String, dynamic>.from(r),
              votedByMe: voted.contains(r['id']),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<GroupRuleEntry?> addRule({
    required String groupId,
    required String itemId,
    required String title,
    required String body,
  }) async {
    final row = await _client
        .from('group_rule_entries')
        .insert({
          'group_id': groupId,
          'item_id': itemId,
          'author_id': _userId,
          'title': title.trim(),
          'body': body.trim(),
        })
        .select()
        .single();
    return GroupRuleEntry.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> toggleVote(String ruleId, bool vote) async {
    if (vote) {
      await voteRule(ruleId);
    } else {
      await unvoteRule(ruleId);
    }
  }

  Future<void> _refreshVoteCount(String ruleId) async {
    final votes = await _client
        .from('group_rule_votes')
        .select('rule_id')
        .eq('rule_id', ruleId);
    final count = (votes as List).length;
    await _client
        .from('group_rule_entries')
        .update({'vote_count': count})
        .eq('id', ruleId);
  }

  Future<void> voteRule(String ruleId) async {
    await _client.from('group_rule_votes').upsert({
      'rule_id': ruleId,
      'voter_id': _userId,
    });
    await _refreshVoteCount(ruleId);
  }

  Future<void> unvoteRule(String ruleId) async {
    await _client
        .from('group_rule_votes')
        .delete()
        .eq('rule_id', ruleId)
        .eq('voter_id', _userId);
    await _refreshVoteCount(ruleId);
  }

  Future<List<GroupWantedPost>> fetchWantedPosts(String groupId) async {
    try {
      final rows = await _client
          .from('group_wanted_posts')
          .select('*, profiles(username)')
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(50);
      return (rows as List)
          .map((r) => GroupWantedPost.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> postWanted({
    required String groupId,
    required String message,
    String? itemId,
    Map<String, dynamic>? catalogPayload,
  }) async {
    await _client.from('group_wanted_posts').insert({
      'group_id': groupId,
      'author_id': _userId,
      'message': message.trim(),
      if (itemId != null) 'item_id': itemId,
      'catalog_payload': catalogPayload ?? {},
    });
  }

  Future<void> claimWanted(String postId) async {
    await _client.from('group_wanted_posts').update({
      'claimed_by': _userId,
      'claimed_at': DateTime.now().toIso8601String(),
    }).eq('id', postId);
  }

  Future<void> releaseClaim(String postId) async {
    await _client.from('group_wanted_posts').update({
      'claimed_by': null,
      'claimed_at': null,
    }).eq('id', postId);
  }

  Future<void> updateRule({
    required String ruleId,
    required String title,
    required String body,
  }) async {
    await _client
        .from('group_rule_entries')
        .update({
          'title': title.trim(),
          'body': body.trim(),
        })
        .eq('id', ruleId)
        .eq('author_id', _userId);
  }
}
