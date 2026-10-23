import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 5 étoiles = note 0.0 → 5.0 (précision 0.1).
/// Hover PC prévisualise ; clic / fin de pan sauvegarde via [onChanged].
class PrecisionStarRatingBar extends StatefulWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final bool readOnly;
  final double starSize;

  const PrecisionStarRatingBar({
    super.key,
    required this.rating,
    required this.onChanged,
    this.readOnly = false,
    this.starSize = 28,
  });

  @override
  State<PrecisionStarRatingBar> createState() => _PrecisionStarRatingBarState();
}

class _PrecisionStarRatingBarState extends State<PrecisionStarRatingBar> {
  /// Note réellement sauvegardée (0 = non noté).
  late double _saved;
  /// Prévisualisation hover / drag (null = afficher [_saved]).
  double? _preview;

  @override
  void initState() {
    super.initState();
    _saved = widget.rating.clamp(0.0, 5.0);
  }

  @override
  void didUpdateWidget(covariant PrecisionStarRatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.rating - widget.rating).abs() > 0.01) {
      _saved = widget.rating.clamp(0.0, 5.0);
      _preview = null;
    }
  }

  double get _display {
    final v = _preview ?? _saved;
    return v.clamp(0.0, 5.0);
  }

  bool get _isUnrated => _display <= 0.001;

  double _ratingFromDx(double dx, double width) {
    if (width <= 0) return 0;
    // Petite marge gauche : clic tout à gauche = 0 (vider).
    final t = (dx / width).clamp(0.0, 1.0);
    final raw = t * 5.0;
    return double.parse((raw * 10).round().clamp(0, 50).toStringAsFixed(0)) /
        10.0;
  }

  void _setPreview(Offset local, double width) {
    final r = _ratingFromDx(local.dx, width);
    if (_preview != null && (r - _preview!).abs() < 0.05) return;
    setState(() => _preview = r);
  }

  void _commitPreview() {
    final r = double.parse((_preview ?? _saved).clamp(0.0, 5.0).toStringAsFixed(1));
    setState(() {
      _saved = r;
      _preview = null;
    });
    if ((r - widget.rating).abs() < 0.05 && r > 0) return;
    // Autorise aussi sauvegarder 0 (clear).
    widget.onChanged(r);
  }

  void _exitHover() {
    if (_preview == null) return;
    setState(() => _preview = null);
  }

  Future<void> _editNumeric() async {
    if (widget.readOnly) return;
    final ctrl = TextEditingController(
      text: _saved <= 0 ? '' : _saved.toStringAsFixed(1),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note /5'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          decoration: const InputDecoration(
            hintText: '4.3',
            suffixText: '/ 5',
          ),
          onSubmitted: (v) {
            if (v.trim().isEmpty) {
              Navigator.pop(ctx, 0.0);
              return;
            }
            final n = double.tryParse(v.replaceAll(',', '.'));
            Navigator.pop(ctx, n);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) {
                Navigator.pop(ctx, 0.0);
                return;
              }
              final n = double.tryParse(ctrl.text.replaceAll(',', '.'));
              Navigator.pop(ctx, n);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    setState(() {
      _saved = result.clamp(0.0, 5.0);
      _preview = null;
    });
    widget.onChanged(_saved);
  }

  @override
  Widget build(BuildContext context) {
    final badgeText =
        _isUnrated ? '— / 5' : '${_display.toStringAsFixed(1)} / 5';

    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return MouseRegion(
                onHover: widget.readOnly
                    ? null
                    : (e) => _setPreview(e.localPosition, width),
                onExit: widget.readOnly ? null : (_) => _exitHover(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: widget.readOnly
                      ? null
                      : (d) => _setPreview(d.localPosition, width),
                  onPanUpdate: widget.readOnly
                      ? null
                      : (d) => _setPreview(d.localPosition, width),
                  onPanEnd: widget.readOnly ? null : (_) => _commitPreview(),
                  onPanCancel: widget.readOnly ? null : _exitHover,
                  onTapUp: widget.readOnly
                      ? null
                      : (d) {
                          _setPreview(d.localPosition, width);
                          _commitPreview();
                        },
                  child: SizedBox(
                    height: widget.starSize + 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: List.generate(5, (i) {
                        // Note 0 → aucune étoile remplie (contours seuls).
                        final fill = _isUnrated
                            ? 0.0
                            : (_display - i).clamp(0.0, 1.0);
                        return Padding(
                          padding: EdgeInsets.only(right: i < 4 ? 6 : 0),
                          child: SizedBox(
                            width: widget.starSize,
                            height: widget.starSize,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Icon(
                                  Icons.star_border_rounded,
                                  size: widget.starSize,
                                  color: Colors.amber.shade700.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                                if (fill > 0.01)
                                  ClipRect(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: fill,
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: widget.starSize,
                                        color: Colors.amber.shade700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: widget.readOnly ? null : _editNumeric,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.amber.shade700.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
