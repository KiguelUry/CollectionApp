import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/rating_colors.dart';

/// 5 étoiles au clic : 1er clic = N.0, 2e = N−0.5, 3e = effacer.
/// Note personnelle = bleu métallique (jamais or communauté).
/// Valeur locale synchrone + debounce 350 ms vers le parent (évite le retour en arrière).
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
  late double _localRating;
  Timer? _debounce;
  static const _debounceMs = 350;

  @override
  void initState() {
    super.initState();
    _localRating = widget.rating.clamp(0.0, 5.0);
  }

  @override
  void didUpdateWidget(covariant PrecisionStarRatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ignore les updates parent pendant le debounce (évite 2.5 → 3.0).
    if (_debounce?.isActive == true) return;
    if ((oldWidget.rating - widget.rating).abs() > 0.01) {
      _localRating = widget.rating.clamp(0.0, 5.0);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool get _isUnrated => _localRating <= 0.001;

  void _commitDebounced(double next) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;
      widget.onChanged(next);
    });
  }

  void _onStarPointer(int starIndex) {
    if (widget.readOnly) return;
    final n = (starIndex + 1).toDouble();
    final full = n;
    final half = n - 0.5;
    double next;
    if ((_localRating - full).abs() < 0.05) {
      next = half;
    } else if ((_localRating - half).abs() < 0.05) {
      next = 0;
    } else {
      next = full;
    }
    next = double.parse(next.clamp(0.0, 5.0).toStringAsFixed(1));
    // Mise à jour locale synchrone immédiate (avant le round-trip Supabase).
    setState(() => _localRating = next);
    _commitDebounced(next);
  }

  Future<void> _editNumeric() async {
    if (widget.readOnly) return;
    final ctrl = TextEditingController(
      text: _isUnrated ? '' : _localRating.toStringAsFixed(1),
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
    setState(() => _localRating = r);
    _commitDebounced(r);
  }

  IconData _iconFor(int i) {
    final threshold = i + 1.0;
    if (_localRating >= threshold - 0.01) return Icons.star_rounded;
    if (_localRating >= threshold - 0.5 - 0.01) return Icons.star_half_rounded;
    return Icons.star_border_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.starColor ?? RatingColors.personal;
    final badge =
        _isUnrated ? '— / 5' : '${_localRating.toStringAsFixed(1)} / 5';
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
                    // onTapDown = réponse synchrone au 1er contact (évite 2.5→3.0).
                    onTapDown: widget.readOnly
                        ? null
                        : (_) => _onStarPointer(i),
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
