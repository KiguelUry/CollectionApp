import 'package:flutter/material.dart';

/// Titre tronqué avec infobulle au survol / appui long.
class ItemTitleText extends StatelessWidget {
  final String title;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;

  const ItemTitleText({
    super.key,
    required this.title,
    this.style,
    this.maxLines = 2,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: title,
      waitDuration: const Duration(milliseconds: 400),
      child: Text(
        title,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
