import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../utils/http_user_agent.dart';
import '../../utils/tcg_set_image_url.dart';
/// Logo extension / bloc (PNG, WebP ou SVG Scryfall) avec URLs de secours.
class TcgSetLogo extends StatefulWidget {
  final List<String> urls;
  final Color fallbackColor;
  final String? fallbackLabel;

  const TcgSetLogo({
    super.key,
    required List<String> urls,
    required this.fallbackColor,
    this.fallbackLabel,
  }) : urls = urls;

  factory TcgSetLogo.forSet({
    Key? key,
    required CardSubcategory subcategory,
    required TcgSetInfo set,
    required Color fallbackColor,
    String? fallbackLabel,
  }) {
    return TcgSetLogo(
      key: key,
      urls: tcgSetLogoCandidates(
        subcategory: subcategory,
        imageUrl: set.imageUrl,
        setId: set.id,
        setCode: set.code,
        seriesId: inferTcgdexSeriesId(set.id),
      ),
      fallbackColor: fallbackColor,
      fallbackLabel: fallbackLabel,
    );
  }

  factory TcgSetLogo.forBlock({
    Key? key,
    required CardSubcategory subcategory,
    required TcgSeriesBlock block,
    required Color fallbackColor,
    String? fallbackLabel,
  }) {
    return TcgSetLogo(
      key: key,
      urls: tcgBlockLogoCandidates(
        subcategory: subcategory,
        block: block,
      ),
      fallbackColor: fallbackColor,
      fallbackLabel: fallbackLabel,
    );
  }

  @override
  State<TcgSetLogo> createState() => _TcgSetLogoState();
}

class _TcgSetLogoState extends State<TcgSetLogo> {
  int _index = 0;

  List<String> get _urls => widget.urls;

  void _tryNext() {
    if (!mounted || _index + 1 >= _urls.length) return;
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    if (_urls.isEmpty) return _fallback();

    final u = _urls[_index.clamp(0, _urls.length - 1)];

    if (u.toLowerCase().endsWith('.svg')) {
      return _SvgLogo(
        key: ValueKey('svg-$u'),
        url: u,
        headers: tcgHttpHeaders,
        onFailed: _tryNext,
        fallback: _fallback(),
      );
    }

    return Image.network(
      u,
      key: ValueKey('img-$u'),
      fit: BoxFit.contain,
      headers: tcgHttpHeaders,
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext());
        return _fallback();
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _fallback();
      },
    );
  }

  Widget _fallback() {
    final label = widget.fallbackLabel?.trim();
    return ColoredBox(
      color: widget.fallbackColor.withValues(alpha: 0.12),
      child: Center(
        child: label != null && label.isNotEmpty
            ? Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: widget.fallbackColor,
                ),
              )
            : Icon(Icons.layers, color: widget.fallbackColor, size: 40),
      ),
    );
  }
}

class _SvgLogo extends StatelessWidget {
  final String url;
  final Map<String, String> headers;
  final VoidCallback onFailed;
  final Widget fallback;

  const _SvgLogo({
    super.key,
    required this.url,
    required this.headers,
    required this.onFailed,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.network(
      url,
      fit: BoxFit.contain,
      headers: headers,
      placeholderBuilder: (_) => fallback,
      // Si le SVG échoue, essayer l'URL suivante (PNG Scryfall, etc.).
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onFailed());
        return fallback;
      },
    );
  }
}
