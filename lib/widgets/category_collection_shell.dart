import 'package:flutter/material.dart';

import '../models/collection_category.dart';

/// Action rapide (icône dans l'en-tête coloré).
class CategoryQuickAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const CategoryQuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// Conservé pour imports existants — le bandeau volumineux n'est plus utilisé ici.
@Deprecated('Use CategoryCollectionHeader instead')
class CategoryCollectionShell extends StatelessWidget {
  final CollectionCategory category;
  final String? subtitle;
  final int personalCount;
  final int groupCount;
  final List<CategoryQuickAction> quickActions;
  final Widget child;

  const CategoryCollectionShell({
    super.key,
    required this.category,
    this.subtitle,
    required this.personalCount,
    required this.groupCount,
    this.quickActions = const [],
    required this.child,
  });

  @override
  Widget build(BuildContext context) => child;
}
