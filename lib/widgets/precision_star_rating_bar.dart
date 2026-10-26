import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/rating_colors.dart';

/// 5 étoiles au clic : 1er clic = N.0, 2e = N−0.5, 3e = effacer.
/// Note personnelle = bleu métallique (jamais or communauté).
class PrecisionStarRatingBar extends StatefulWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final bool readOnly;
  final double starSize;
  final Color? starColor;

  const PrecisionStarRatingBar({
    super.key,
    required this.rating,
    required this.onChanged,
    this.readOnly = false,
    this.starSize = 32,
    this.starColor,
  });

  @override
  State<PrecisionStarRatingBar> createState() => _PrecisionStarRatingBarState();
}

class _PrecisionStarRatingBarState extends State<PrecisionStarRatingBar> {
  late double _saved;

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
    }
  }

  bool get _isUnrated => _saved <= 0.001;

  void _onStarTap(int starIndex) {
    if (widget.readOnly) return;
    // starIndex 0..4 → étoile N = starIndex+1
    final n = (starIndex + 1).toDouble();
    final full = n;
    final half = n - 0.5;
    double next;
    if ((_saved - full).abs() < 0.05) {
      // Déjà N.0 → demi
      next = half;
    } else if ((_saved - half).abs() < 0.05) {
      // Déjà N−0.5 → effacer
      next = 0;
    } else {
      // Autre valeur → entier N.0
      next = full;
    }
    next = double.parse(next.clamp(0.0, 5.0).toStringAsFixed(1));
    setState(() => _saved = next);
    widget.onChanged(next);
  }

  Future<void> _editNumeric() async {
    if (widget.readOnly) return;
    final ctrl = TextEditingController(
      text: _isUnrated ? '' : _saved.toStringAsFixed(1),
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
            hintText: '4.5',
            suffixText: '/ 5',
          ),
          onSubmitted: (v) {
            if (v.trim().isEmpty) {
              Navigator.pop(ctx, 0.0);
              return;
            }
            Navigator.pop(ctx, double.tryParse(v.replaceAll(',', '.')));
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
              Navigator.pop(
                ctx,
                double.tryParse(ctrl.text.replaceAll(',', '.')),
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    final r = double.parse(result.clamp(0.0, 5.0).toStringAsFixed(1));
    setState(() => _saved = r);
    widget.onChanged(r);
  }

  IconData _iconFor(int i) {
    final threshold = i + 1.0;
    if (_saved >= threshold - 0.01) return Icons.star_rounded;
    if (_saved >= threshold - 0.5 - 0.01) return Icons.star_half_rounded;
    return Icons.star_border_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.starColor ?? RatingColors.personal;
    final badge = _isUnrated ? '— / 5' : '${_saved.toStringAsFixed(1)} / 5';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: EdgeInsets.only(right: i < 4 ? 2 : 0),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.readOnly ? null : () => _onStarTap(i),
                    customBorder: const CircleBorder(),
                    child: Icon(
                      _iconFor(i),
                      size: widget.starSize.clamp(18, 28),
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          InkWell(
            onTap: widget.readOnly ? null : _editNumeric,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: RatingColors.personalDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
