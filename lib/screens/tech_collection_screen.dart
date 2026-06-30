import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../models/tech_subcategory.dart';
import '../theme/category_hub_theme.dart';
import '../widgets/category_catalog_hub_body.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import 'home_screen.dart';

/// Hub Électronique & High-Tech.
class TechCollectionScreen extends StatelessWidget {
  const TechCollectionScreen({super.key});

  static final _accent = const Color(0xFF3949AB);
  static final _theme = CategoryHubTheme.tech(_accent);

  void _openHomeAll(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HomeScreen(
          category: CollectionCategory.tech,
          screenTitle: 'High-Tech',
        ),
      ),
    );
  }

  void _openHome(
    BuildContext context, {
    required TechSubcategory sub,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HomeScreen(
          category: CollectionCategory.tech,
          screenTitle: sub.label,
          fixedTechSubcategory: sub,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryHubHeader(title: 'High-Tech', accentColor: _accent),
          Expanded(
            child: CategoryCatalogHubBody(
              hubTitle: 'High-Tech',
              theme: _theme,
              onSearch: () => _openHomeAll(context),
              onClassicList: () => _openHomeAll(context),
              items: [
                for (final sub in TechSubcategory.values)
                  CategoryTypeHubItem(
                    label: sub.label,
                    description: sub.description,
                    icon: sub.icon,
                    color: sub.color,
                    onTap: () => _openHome(context, sub: sub),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
