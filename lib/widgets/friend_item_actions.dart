import 'package:flutter/material.dart';

import '../models/collection_item.dart';
import '../utils/copy_friend_item.dart';
import '../utils/friend_item_overlap.dart';

/// Bandeau d'actions sur l'objet d'un ami : emprunter, wishlist, copier.
class FriendItemActions extends StatefulWidget {
  final CollectionItem item;
  final String friendUsername;
  final FriendOverlapKind? overlap;

  const FriendItemActions({
    super.key,
    required this.item,
    required this.friendUsername,
    this.overlap,
  });

  @override
  State<FriendItemActions> createState() => _FriendItemActionsState();
}

class _FriendItemActionsState extends State<FriendItemActions> {
  bool _borrowBusy = false;
  bool _wishBusy = false;
  bool _borrowSent = false;
  late FriendOverlapKind _overlap = widget.overlap ?? FriendOverlapKind.none;

  Future<void> _borrow() async {
    final messageCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Emprunter « ${widget.item.title} »'),
        content: TextField(
          controller: messageCtrl,
          maxLength: 140,
          decoration: InputDecoration(
            hintText: 'Un mot pour ${widget.friendUsername} (optionnel)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    final note = messageCtrl.text;
    messageCtrl.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _borrowBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final msg = await requestBorrowFriendItem(widget.item, message: note);
      if (mounted) setState(() => _borrowSent = true);
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Envoi impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _borrowBusy = false);
    }
  }

  Future<void> _wishlist() async {
    setState(() => _wishBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final msg = await addFriendItemToWishlist(widget.item);
      if (mounted && msg.contains('ajouté')) {
        setState(() => _overlap = FriendOverlapKind.inWishlist);
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Ajout impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _wishBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final owned = _overlap == FriendOverlapKind.inCollection;
    final wished = _overlap == FriendOverlapKind.inWishlist;
    final canBorrow = !widget.item.isWishlist && widget.item.addedBy != null;
    final status = owned
        ? 'Tu as aussi ce jeu'
        : wished
            ? 'Déjà dans ta wishlist'
            : null;

    Widget spinner() => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.item.isWishlist
                      ? 'Dans la wishlist de ${widget.friendUsername}'
                      : 'Chez ${widget.friendUsername}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (status != null)
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: owned ? Colors.green.shade700 : Colors.amber.shade800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canBorrow)
                FilledButton.tonal(
                  key: const ValueKey('friend_item_borrow'),
                  onPressed: _borrowBusy || _borrowSent ? null : _borrow,
                  child: _borrowBusy
                      ? spinner()
                      : Text(
                          _borrowSent
                              ? '🤝 Demande envoyée'
                              : '🤝 Demander à emprunter',
                        ),
                ),
              if (!owned)
                OutlinedButton(
                  key: const ValueKey('friend_item_wishlist'),
                  onPressed: _wishBusy || wished ? null : _wishlist,
                  child: _wishBusy
                      ? spinner()
                      : Text(
                          wished ? '❤️ Dans ta wishlist' : '❤️ Ajouter à ma wishlist',
                        ),
                ),
              if (!owned)
                TextButton(
                onPressed: () => showCopyFriendItemSheet(
                  context,
                  source: widget.item,
                  friendUsername: widget.friendUsername,
                ),
                child: const Text('Je l\'ai aussi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
