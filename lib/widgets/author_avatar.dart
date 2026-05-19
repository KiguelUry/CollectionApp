import 'package:flutter/material.dart';

import '../services/open_library_service.dart';
import 'collection_cover_image.dart';

/// Photo auteur (Open Library) ou initiale.
class AuthorAvatar extends StatefulWidget {
  final String authorName;
  final double radius;

  const AuthorAvatar({
    super.key,
    required this.authorName,
    this.radius = 24,
  });

  @override
  State<AuthorAvatar> createState() => _AuthorAvatarState();
}

class _AuthorAvatarState extends State<AuthorAvatar> {
  String? _photoUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AuthorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authorName != widget.authorName) {
      _photoUrl = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final url = await OpenLibraryService.lookupAuthorPhotoUrl(widget.authorName);
    if (mounted) {
      setState(() {
        _photoUrl = url;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    if (_loading) {
      return CircleAvatar(
        radius: widget.radius,
        child: SizedBox(
          width: widget.radius,
          height: widget.radius,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return ClipOval(
        child: CollectionCoverImage(
          url: _photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final initial =
        widget.authorName.isNotEmpty ? widget.authorName[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: widget.radius,
      child: Text(
        initial,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: widget.radius * 0.9,
        ),
      ),
    );
  }
}
