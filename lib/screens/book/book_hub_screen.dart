import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../widgets/app_app_bar.dart';
import 'book_discover_screen.dart';
import 'book_reading_pile_screen.dart';

/// Hub Lecture : Pile à lire + Trous + Sorties & Découvrir.
class BookHubScreen extends StatefulWidget {
  const BookHubScreen({super.key});

  @override
  State<BookHubScreen> createState() => _BookHubScreenState();
}

class _BookHubScreenState extends State<BookHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = BookAccent.primary;
    return Scaffold(
      appBar: AppAppBar(
        title: 'Hub Lecture',
        backgroundColor: accent,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '📖 Pile'),
            Tab(text: '🧩 Trous'),
            Tab(text: '✨ Découvrir'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          BookReadingPileScreen(embedded: true, initialTab: 0),
          BookReadingPileScreen(embedded: true, initialTab: 1),
          BookDiscoverScreen(embedded: true),
        ],
      ),
    );
  }
}
