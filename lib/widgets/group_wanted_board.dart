import 'package:flutter/material.dart';

import '../../services/group_community_service.dart';
import '../collection_cover_image.dart';

class GroupWantedBoard extends StatefulWidget {
  final String groupId;
  final Color accent;

  const GroupWantedBoard({
    super.key,
    required this.groupId,
    required this.accent,
  });

  @override
  State<GroupWantedBoard> createState() => _GroupWantedBoardState();
}

class _GroupWantedBoardState extends State<GroupWantedBoard> {
  final _service = GroupCommunityService();
  final _messageController = TextEditingController();
  bool _loading = true;
  List<GroupWantedPost> _posts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final posts = await _service.fetchWantedPosts(widget.groupId);
    if (mounted) {
      setState(() {
        _posts = posts;
        _loading = false;
      });
    }
  }

  Future<void> _post() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) return;
    await _service.postWanted(groupId: widget.groupId, message: msg);
    _messageController.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: widget.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Mur des souhaits',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Alerte le groupe : « Il nous faut cet objet ! »',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Ex. On a besoin de Wingspan Europe !',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _post(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _post,
                icon: const Icon(Icons.send_rounded),
                style: IconButton.styleFrom(backgroundColor: widget.accent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'Aucune alerte pour l\'instant.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            for (final post in _posts) ...[
              _WantedCard(
                post: post,
                accent: widget.accent,
                onClaim: () async {
                  await _service.claimWanted(post.id);
                  _load();
                },
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _WantedCard extends StatelessWidget {
  final GroupWantedPost post;
  final Color accent;
  final VoidCallback onClaim;

  const _WantedCard({
    required this.post,
    required this.accent,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final claimed = post.claimedBy != null;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CollectionCoverImage(
                  url: post.imageUrl!,
                  width: 48,
                  height: 68,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: 48,
                height: 68,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.campaign_outlined, color: accent),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.message,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (post.linkedTitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      post.linkedTitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    post.authorName ?? 'Membre',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (!claimed)
              TextButton.icon(
                onPressed: onClaim,
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: const Text('Je m\'en occupe'),
              )
            else
              Chip(
                label: const Text('En cours'),
                avatar: Icon(Icons.check, size: 16, color: accent),
              ),
          ],
        ),
      ),
    );
  }
}
