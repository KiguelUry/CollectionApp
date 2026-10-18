import 'package:flutter/material.dart';

import '../models/item_condition.dart';

Color itemConditionColor(BuildContext context, ItemCondition? condition) =>
    switch (condition) {
      ItemCondition.neuf => Colors.green.shade600,
      ItemCondition.tresBon => Colors.teal.shade600,
      ItemCondition.bon => Colors.blue.shade600,
      ItemCondition.correct => Colors.orange.shade700,
      ItemCondition.use => Colors.red.shade600,
      null => Theme.of(context).colorScheme.outline,
    };

/// Pastille colorée de l'état d'un exemplaire.
class ItemConditionPill extends StatelessWidget {
  final ItemCondition? condition;

  const ItemConditionPill({super.key, this.condition});

  @override
  Widget build(BuildContext context) {
    final color = itemConditionColor(context, condition);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        condition?.label ?? 'État ?',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
