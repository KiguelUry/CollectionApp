import 'package:flutter/material.dart';

import '../theme/category_hub_theme.dart';
import 'category_type_hub.dart';
import 'ui/hub_search_bar.dart';

/// Corps de hub catalogue (hero + recherche + grille) avec DA par catégorie.
class CategoryCatalogHubBody extends StatelessWidget {
  final String hubTitle;
  final CategoryHubTheme theme;
  final List<CategoryTypeHubItem> items;
  final VoidCallback onSearch;
  final VoidCallback? onClassicList;

  const CategoryCatalogHubBody({
    super.key,
    required this.hubTitle,
    required this.theme,
    required this.items,
    required this.onSearch,
    this.onClassicList,
  });

  @override
  Widget build(BuildContext context) {
    return CategoryTypeHub(
      accentColor: theme.accent,
      title: hubTitle,
      showTitleInHero: false,
      subtitle: theme.tagline,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (theme.sourceChips.isNotEmpty) ...[
            _SourceChipsRow(chips: theme.sourceChips, accent: theme.accent),
            const SizedBox(height: 12),
          ],
          HubSearchBar(
            accent: theme.accent,
            hint: theme.searchHint,
            subtitle: theme.searchSubtitle,
            icon: theme.searchIcon,
            onTap: onSearch,
          ),
        ],
      ),
      items: items,
      onClassicList: onClassicList,
      heroWatermark: theme.watermarkIcon,
    );
  }
}

class _SourceChipsRow extends StatelessWidget {
  final List<HubSourceChip> chips;
  final Color accent;

  const _SourceChipsRow({required this.chips, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(c.icon, size: 14, color: accent),
                const SizedBox(width: 6),
                Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
