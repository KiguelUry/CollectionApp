import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 5 étoiles = note 0.0 → 5.0 (précision 0.1).
/// Glisser/cliquer directement sur les étoiles ; [onChanged] uniquement en fin de geste.
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
  late double _local;
  double? _committed;

  @override
  void initState() {
    super.initState();
    _local = widget.rating.clamp(0.0, 5.0);
    _committed = _local;
  }

  @override
  void didUpdateWidget(covariant PrecisionStarRatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.rating - widget.rating).abs() > 0.01) {
      _local = widget.rating.clamp(0.0, 5.0);
      _committed = _local;
    }
  }

  double _ratingFromDx(double dx, double width) {
    if (width <= 0) return 0;
    final t = (dx / width).clamp(0.0, 1.0);
    final raw = t * 5.0;
    return double.parse((raw * 10).round().clamp(0, 50).toStringAsFixed(0)) /
        10.0;
  }

  void _preview(Offset local, double width) {
    final r = _ratingFromDx(local.dx, width);
    if ((r - _local).abs() < 0.05) return;
    setState(() => _local = r);
  }

  void _commit() {
    final r = double.parse(_local.clamp(0.0, 5.0).toStringAsFixed(1));
    if (_committed != null && (r - _committed!).abs() < 0.05) return;
    _committed = r;
    widget.onChanged(r);
  }

  Future<void> _editNumeric() async {
    if (widget.readOnly) return;
    final ctrl = TextEditingController(text: _local.toStringAsFixed(1));
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
    setState(() => _local = result.clamp(0.0, 5.0));
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: widget.readOnly
                    ? null
                    : (d) => _preview(d.localPosition, width),
                onPanUpdate: widget.readOnly
                    ? null
                    : (d) => _preview(d.localPosition, width),
                onPanEnd: widget.readOnly ? null : (_) => _commit(),
                onPanCancel: widget.readOnly ? null : _commit,
                onTapUp: widget.readOnly
                    ? null
                    : (d) {
                        _preview(d.localPosition, width);
                        _commit();
                      },
                child: SizedBox(
                  height: widget.starSize + 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(5, (i) {
                      final fill = (_local - i).clamp(0.0, 1.0);
                      return Padding(
                        padding: EdgeInsets.only(right: i < 4 ? 6 : 0),
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
              '${_local.toStringAsFixed(1)} / 5',
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
