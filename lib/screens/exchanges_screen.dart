import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../services/collection_refresh.dart';
import '../services/inventory_service.dart';
import '../services/loan_service.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/item_copy_units.dart';
import '../utils/marketplace_status.dart';
import '../utils/wishlist_market_metadata.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/bgg_network_image.dart';
import '../widgets/item_condition_pill.dart';
import 'item_detail_screen.dart';
import 'marketplace/marketplace_screen.dart';

/// Prêts en cours, doublons (détail par exemplaire) et objets à vendre.
class ExchangesScreen extends StatefulWidget {
  final int initialTab;

  const ExchangesScreen({super.key, this.initialTab = 0});

  @override
  State<ExchangesScreen> createState() => _ExchangesScreenState();
}

class _CopyView {
  final CollectionItem item;
  final String label;
  final ItemCondition? condition;
  final double? price;
  final String location;
  final bool onLoan;

  const _CopyView({
    required this.item,
    required this.label,
    required this.condition,
    required this.price,
    required this.location,
    this.onLoan = false,
  });
}

class _ExchangesScreenState extends State<ExchangesScreen> {
  final _inventory = InventoryService();
  final _loanService = LoanService();
  List<CollectionItem> _owned = [];
  List<CollectionItem> _loans = [];
  bool _loading = true;

  String? get _meUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _inventory.fetchOwnedItems(),
        _loanService.fetchActiveLoans(),
      ]);
      _owned = results[0];
      _loans = results[1];
    } catch (_) {
      _owned = [];
      _loans = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  List<GroupedCollectionItem> get _duplicates => CollectionGridGrouper.group(
        _owned.where((i) => !i.isWishlist && !i.isSold).toList(),
      ).where((g) => g.hasDuplicates).toList();

  List<CollectionItem> get _forSale => _owned
      .where(
        (i) => !i.isSold && !i.isWishlist && (i.isForSale || itemWantsTrade(i)),
      )
      .toList()
    ..sort((a, b) => a.title.compareTo(b.title));

  List<CollectionItem> get _sold =>
      _owned.where((i) => i.isSold).toList()
        ..sort((a, b) => a.title.compareTo(b.title));

  List<_CopyView> _copiesFor(GroupedCollectionItem group) {
    final byId = {for (final i in _owned) i.id: i};
    final out = <_CopyView>[];
    for (final id in group.itemIds) {
      final item = byId[id];
      if (item == null) continue;
      if (itemUsesCopyUnits(item)) {
        final units = readCopyUnits(item);
        for (var i = 0; i < units.length; i++) {
          final u = units[i];
          out.add(
            _CopyView(
              item: item,
              label: u.defaultLabel(out.length + 1),
              condition: u.condition,
              price: u.purchasePrice,
              location: item.isOnLoan
                  ? 'Prêté → ${item.loaneeDisplayName}'
                  : _chez(holderLabelForCopyUnit(u)),
              onLoan: item.isOnLoan,
            ),
          );
        }
      } else {
        out.add(
          _CopyView(
            item: item,
            label: 'Exemplaire ${out.length + 1}',
            condition: item.itemCondition,
            price: item.purchasePrice,
            location: quickWhereaboutsSummaryLabel(item, meUserId: _meUserId),
            onLoan: item.isOnLoan,
          ),
        );
      }
    }
    return out;
  }

  static String _chez(String label) {
    final t = label.trim();
    if (t.isEmpty) return 'Chez moi';
    final lower = t.toLowerCase();
    if (lower.startsWith('chez ') || lower.startsWith('à ')) return t;
    return 'Chez $t';
  }

  Future<void> _openItem(CollectionItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
    );
    if (mounted) _load();
  }

  Future<void> _setForSale(CollectionItem item, bool value) async {
    await _inventory.setForSale(item.id, value);
    CollectionRefresh.instance.bump();
    await _load();
  }

  Future<void> _returnLoan(CollectionItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Objet rendu ?'),
        content: Text(
          '« ${item.title} » n\'est plus chez ${item.loaneeDisplayName} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marquer rendu'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _loanService.returnItem(item.id);
      CollectionRefresh.instance.bump();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prêt clôturé')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final duplicates = _duplicates;
    final forSale = _forSale;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppAppBar(
          title: 'Échanges & Doublons',
          actions: [
            IconButton(
              tooltip: 'Hôtel des ventes',
              icon: const Icon(Icons.storefront_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
              ),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: _tabLabel('Prêts en cours', _loans.length)),
              Tab(text: _tabLabel('Doublons', duplicates.length)),
              Tab(text: _tabLabel('À vendre', forSale.length)),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _wrap(_buildLoans()),
                  _wrap(_buildDuplicates(duplicates)),
                  _wrap(_buildForSale(forSale)),
                ],
              ),
      ),
    );
  }

  String _tabLabel(String label, int count) =>
      _loading || count == 0 ? label : '$label ($count)';

  Widget _wrap(Widget child) => RefreshIndicator(
        onRefresh: _load,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: child,
          ),
        ),
      );

  // ---------------------------------------------------------------- Prêts

  Widget _buildLoans() {
    if (_loans.isEmpty) {
      return _empty(
        icon: Icons.handshake_outlined,
        title: 'Aucun prêt en cours',
        hint: 'Depuis la fiche d\'un objet, « Prêter » pour suivre qui a ton '
            'jeu, ton manga…',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      itemCount: _loans.length,
      itemBuilder: (context, i) {
        final item = _loans[i];
        final days = item.loanedAt == null
            ? null
            : DateTime.now().difference(item.loanedAt!).inDays;
        final accent = days == null
            ? Colors.blue.shade600
            : days >= 30
                ? Colors.red.shade700
                : days >= 14
                    ? Colors.orange.shade800
                    : Colors.blue.shade600;
        return _ItemCard(
          item: item,
          onTap: () => _openItem(item),
          subtitle: '→ ${item.loaneeDisplayName}',
          trailing: FilledButton.tonalIcon(
            onPressed: () => _returnLoan(item),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Rendu'),
          ),
          footer: Row(
            children: [
              _Tag(
                icon: Icons.schedule,
                label: days == null
                    ? 'Date inconnue'
                    : days < 1
                        ? 'Depuis aujourd\'hui'
                        : 'Depuis $days j',
                color: accent,
              ),
              if (days != null && days >= 30) ...[
                const SizedBox(width: 6),
                _Tag(
                  icon: Icons.notifications_active_outlined,
                  label: 'À relancer',
                  color: accent,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- Doublons

  Widget _buildDuplicates(List<GroupedCollectionItem> duplicates) {
    if (duplicates.isEmpty) {
      return _empty(
        icon: Icons.copy_all,
        title: 'Aucun doublon',
        hint: 'Les objets possédés en plusieurs exemplaires apparaîtront ici.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      itemCount: duplicates.length,
      itemBuilder: (context, i) {
        final group = duplicates[i];
        final item = group.item;
        final copies = _copiesFor(group);
        final market = marketSecondhandPriceFromMetadata(item.metadata);
        final anyForSale = copies.any((c) => c.item.isForSale);
        return _ItemCard(
          item: item,
          onTap: () => _openItem(item),
          subtitle: [
            '${group.totalQuantity} exemplaires',
            item.category.label,
            if (market != null) 'occasion ≈ ${formatEuroChip(market)}',
          ].join(' · '),
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'sale') _setForSale(item, !anyForSale);
              if (action == 'detail') _openItem(item);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'sale',
                child: Text(
                  anyForSale ? 'Retirer de la vente' : 'Mettre un exemplaire en vente',
                ),
              ),
              const PopupMenuItem(value: 'detail', child: Text('Voir la fiche')),
            ],
          ),
          footer: Column(
            children: [for (final c in copies) _CopyRow(copy: c)],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- À vendre

  Widget _buildForSale(List<CollectionItem> forSale) {
    final sold = _sold;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.5),
          child: ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Hôtel des ventes'),
            subtitle: const Text(
              'Ce que tes amis et groupes vendent ou échangent',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (forSale.isEmpty)
          _empty(
            icon: Icons.sell_outlined,
            title: 'Rien à vendre pour l\'instant',
            hint: 'Depuis un doublon ou une fiche, active « À vendre » ou '
                '« À échanger ».',
            shrink: true,
          )
        else
          for (final item in forSale) _forSaleCard(item),
        if (sold.isNotEmpty) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.history),
            title: Text('Déjà vendus (${sold.length})'),
            children: [
              for (final item in sold)
                _ItemCard(
                  item: item,
                  dimmed: true,
                  onTap: () => _openItem(item),
                  subtitle: item.category.label,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _forSaleCard(CollectionItem item) {
    final intent = listingIntent(item);
    final market = marketSecondhandPriceFromMetadata(item.metadata);
    final paid = item.purchasePrice;
    return _ItemCard(
      item: item,
      onTap: () => _openItem(item),
      subtitle: item.category.label,
      trailing: IconButton(
        tooltip: 'Retirer de la vente',
        icon: const Icon(Icons.close),
        onPressed: () => _setForSale(item, false),
      ),
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _Tag(
            icon: intent == ItemListingIntent.wantsTrade
                ? Icons.swap_horiz
                : Icons.sell_outlined,
            label: listingIntentLabel(intent),
            color: intent == ItemListingIntent.wantsTrade
                ? Colors.purple.shade500
                : Colors.green.shade700,
          ),
          if (item.itemCondition != null)
            ItemConditionPill(condition: item.itemCondition),
          if (paid != null && paid > 0)
            _Tag(
              icon: Icons.receipt_long_outlined,
              label: 'Payé ${formatEuroChip(paid)}',
              color: Colors.indigo.shade400,
            ),
          if (market != null)
            _Tag(
              icon: Icons.trending_up,
              label: 'Marché ≈ ${formatEuroChip(market)}',
              color: Colors.teal.shade600,
            ),
          _Tag(
            icon: Icons.place_outlined,
            label: quickWhereaboutsSummaryLabel(item, meUserId: _meUserId),
            color: Colors.deepOrange.shade400,
          ),
        ],
      ),
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String hint,
    bool shrink = false,
  }) {
    final content = Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
    if (shrink) return content;
    // ListView pour que le tirer-pour-rafraîchir marche aussi à vide.
    return ListView(children: [const SizedBox(height: 60), content]);
  }
}

class _ItemCard extends StatelessWidget {
  final CollectionItem item;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback onTap;
  final bool dimmed;

  const _ItemCard({
    required this.item,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.footer,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: dimmed ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: item.imageUrl != null
                            ? BggNetworkImage(
                                url: item.imageUrl!,
                                width: 56,
                                height: 56,
                                compact: true,
                              )
                            : ColoredBox(
                                color: item.category.color
                                    .withValues(alpha: 0.15),
                                child: Icon(
                                  item.category.icon,
                                  color: item.category.color,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                if (footer != null) ...[
                  const SizedBox(height: 10),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final _CopyView copy;

  const _CopyRow({required this.copy});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 15,
            color: Colors.teal.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              copy.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  copy.onLoan ? Icons.handshake_outlined : Icons.place_outlined,
                  size: 13,
                  color: copy.onLoan
                      ? Colors.blue.shade600
                      : Colors.deepOrange.shade400,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    copy.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          ItemConditionPill(condition: copy.condition),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              formatEuroChip(copy.price),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Tag({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
