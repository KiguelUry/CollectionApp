import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/rating_colors.dart';

/// 5 étoiles. La 1re étoile cycle `1.0 → 0.5 → 0.0 → null`.
/// Le badge `— / 5` bascule vers `0.0` ou efface la note.
/// `null` = non noté. `0.0` = zéro explicite.
class PrecisionStarRatingBar extends StatefulWidget {
  final double? rating;
  final ValueChanged<double?> onChanged;
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
  double? _localRating;
  Timer? _debounce;
  static const _debounceMs = 350;

  @override
  void initState() {
    super.initState();
    _localRating = _clamp(widget.rating);
  }

  @override
  void didUpdateWidget(covariant PrecisionStarRatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_debounce?.isActive == true) return;
    if (oldWidget.rating != widget.rating) {
      _localRating = _clamp(widget.rating);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  double? _clamp(double? value) {
    if (value == null || value < 0) return null;
    return double.parse(value.clamp(0.0, 5.0).toStringAsFixed(1));
  }

  bool get _isUnrated => _localRating == null;

  void _commitDebounced(double? next) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;
      widget.onChanged(next);
    });
  }

  void _set(double? next) {
    setState(() => _localRating = next);
    _commitDebounced(next);
  }

  void _onStarPointer(int starIndex) {
    if (widget.readOnly) return;
    final n = (starIndex + 1).toDouble();
    final current = _localRating;
    if (starIndex == 0) {
      if (current == null) {
        _set(1.0);
      } else if ((current - 1.0).abs() < 0.05) {
        _set(0.5);
      } else if ((current - 0.5).abs() < 0.05) {
        _set(0.0);
      } else if (current <= 0.001) {
        _set(null);
      } else {
        _set(1.0);
      }
      return;
    }
    final full = n;
    final half = n - 0.5;
    if (current != null && (current - full).abs() < 0.05) {
      _set(half);
    } else if (current != null && (current - half).abs() < 0.05) {
      _set(null);
    } else {
      _set(full);
    }
  }

  void _onBadgeTap() {
    if (widget.readOnly) return;
    if (_localRating == null) {
      _set(0.0);
    } else if (_localRating! <= 0.001) {
      _set(null);
    } else {
      _set(0.0);
    }
  }

  Future<void> _editNumeric() async {
    if (widget.readOnly) return;
    final ctrl = TextEditingController(
      text: _isUnrated ? '' : _localRating!.toStringAsFixed(1),
    );
    var apply = false;
    final result = await showDialog<double?>(
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
            hintText: '0.0 à 5.0',
            suffixText: '/ 5',
          ),
          onSubmitted: (v) {
            apply = true;
            if (v.trim().isEmpty) {
              Navigator.pop(ctx, null);
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
          TextButton(
            onPressed: () {
              apply = true;
              Navigator.pop(ctx, null);
            },
            child: const Text('Effacer'),
          ),
          FilledButton(
            onPressed: () {
              apply = true;
              if (ctrl.text.trim().isEmpty) {
                Navigator.pop(ctx, null);
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
    if (!mounted || !apply) return;
    _set(result == null ? null : _clamp(result));
  }

  IconData _iconFor(int i) {
    final value = _localRating;
    if (value == null || value <= 0.001) return Icons.star_border_rounded;
    final threshold = i + 1.0;
    if (value >= threshold - 0.01) return Icons.star_rounded;
    if (value >= threshold - 0.5 - 0.01) return Icons.star_half_rounded;
    return Icons.star_border_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.starColor ?? RatingColors.personal;
    final badge = _isUnrated
        ? '— / 5'
        : '${_localRating!.toStringAsFixed(1)} / 5';
    return Row(
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
                  onTapDown: widget.readOnly ? null : (_) => _onStarPointer(i),
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
          onTap: widget.readOnly ? null : _onBadgeTap,
          onLongPress: widget.readOnly ? null : _editNumeric,
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
                color: _isUnrated
                    ? RatingColors.personalDark
                    : ratingColor(_localRating!),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
