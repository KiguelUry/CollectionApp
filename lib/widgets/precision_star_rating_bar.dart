import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 10 étoiles = note 0.0 → 10.0 (1 étoile = 1 point), glisser via Slider natif.
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

  void _set(double v) {
    final r = double.parse(v.clamp(0.0, 10.0).toStringAsFixed(1));
    if ((r - _local).abs() < 0.05) {
      setState(() => _local = r);
      return;
    }
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
    _set(result);
  }

  @override
  Widget build(BuildContext context) {
    final starH = widget.starSize + 4;
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                child: SizedBox(
                  height: starH,
                  child: Row(
                    children: List.generate(10, (i) {
                      final fill = (_local - i).clamp(0.0, 1.0);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0.5),
                          child: SizedBox(
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
                        ),
                      );
                    }),
                  ),
                ),
              ),
              if (!widget.readOnly)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 18,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: Colors.amber.shade700.withValues(
                      alpha: 0.35,
                    ),
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.amber.shade800,
                    overlayColor: Colors.amber.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _local,
                    min: 0,
                    max: 10,
                    divisions: 100,
                    onChanged: _set,
                  ),
                ),
            ],
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
