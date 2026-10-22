import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 5 étoiles = note 0.0 → 10.0, glisser pour le dixième près.
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
    this.starSize = 36,
  });

  @override
  State<PrecisionStarRatingBar> createState() => _PrecisionStarRatingBarState();
}

class _PrecisionStarRatingBarState extends State<PrecisionStarRatingBar> {
  final _starsKey = GlobalKey();
  late double _local;

  @override
  void initState() {
    super.initState();
    _local = widget.rating.clamp(0.0, 10.0);
  }

  @override
  void didUpdateWidget(covariant PrecisionStarRatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.rating - widget.rating).abs() > 0.01) {
      _local = widget.rating.clamp(0.0, 10.0);
    }
  }

  double _ratingFromDx(double dx, double width) {
    if (width <= 0) return 0;
    final t = (dx / width).clamp(0.0, 1.0);
    final raw = t * 10.0;
    // Pas de 0.1
    return double.parse((raw * 10).round().clamp(0, 100).toStringAsFixed(0)) /
        10.0;
  }

  void _updateFromLocal(Offset local) {
    final box = _starsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final r = _ratingFromDx(local.dx, box.size.width);
    if ((r - _local).abs() < 0.05) return;
    setState(() => _local = r);
    widget.onChanged(r);
  }

  Future<void> _editNumeric() async {
    if (widget.readOnly) return;
    final ctrl = TextEditingController(text: _local.toStringAsFixed(1));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note /10'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          decoration: const InputDecoration(
            hintText: '8.3',
            suffixText: '/ 10',
          ),
          onSubmitted: (v) {
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
    final r = double.parse(result.clamp(0, 10).toStringAsFixed(1));
    setState(() => _local = r);
    widget.onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.readOnly
                ? null
                : (d) => _updateFromLocal(d.localPosition),
            onHorizontalDragUpdate: widget.readOnly
                ? null
                : (d) => _updateFromLocal(d.localPosition),
            child: SizedBox(
              key: _starsKey,
              height: widget.starSize + 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  // Chaque étoile = 2 points sur 10.
                  final fill = ((_local / 2.0) - i).clamp(0.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: SizedBox(
                      width: widget.starSize,
                      height: widget.starSize,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Icon(
                            Icons.star_border,
                            size: widget.starSize,
                            color: Colors.amber.shade700,
                          ),
                          ClipRect(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: fill,
                              child: Icon(
                                Icons.star,
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
              border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
            ),
            child: Text(
              '${_local.toStringAsFixed(1)} / 10',
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
