import 'package:flutter/material.dart';

import '../../utils/collection_grid_layout.dart';

/// Grille ou liste de placeholders pendant le chargement.
class LoadingPlaceholder extends StatelessWidget {
  final int count;
  final bool grid;
  final String? message;

  const LoadingPlaceholder({
    super.key,
    this.count = 6,
    this.grid = true,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final body = grid
        ? _buildGrid(context)
        : _buildList();

    if (message == null || message!.trim().isEmpty) return body;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            message!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildGrid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: CollectionGridLayout.gridDelegate(
        context,
        mobileColumns: 2,
        childAspectRatio: 0.92,
        spacing: 14,
      ),
      itemCount: count,
      itemBuilder: (_, _) => const _ShimmerBox(height: 120),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => const _ShimmerBox(height: 72),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double height;

  const _ShimmerBox({required this.height});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment(-1 + _ctrl.value * 2, 0),
              end: Alignment(1 + _ctrl.value * 2, 0),
              colors: [
                base.withValues(alpha: 0.5),
                base,
                base.withValues(alpha: 0.5),
              ],
            ),
          ),
        );
      },
    );
  }
}
