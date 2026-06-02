import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import 'home_screen.dart';

/// Hub montres & bracelets.
class WatchCollectionScreen extends StatelessWidget {
  const WatchCollectionScreen({super.key});

  static final _accent = Colors.blueGrey.shade700;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryHubHeader(
            title: 'Montres',
            accentColor: _accent,
          ),
          Expanded(
            child: CategoryTypeHub(
              accentColor: _accent,
              title: 'Montres',
              showTitleInHero: false,
              subtitle:
                  'Marque, modèle, référence — saisie manuelle pour l\'instant.',
              items: [
                CategoryTypeHubItem(
                  label: 'Ma collection',
                  description: 'Toutes tes montres',
                  icon: Icons.watch,
                  color: _accent,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => const HomeScreen(
                          category: CollectionCategory.watch,
                          screenTitle: 'Montres',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
