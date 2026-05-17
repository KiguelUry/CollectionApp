import 'package:flutter/material.dart';
import '../models/collection_item.dart';
import '../services/loan_service.dart';
import '../widgets/bgg_network_image.dart';
import '../widgets/main_drawer.dart';
import 'item_detail_screen.dart';

/// Registre des objets actuellement prêtés.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  final _loanService = LoanService();
  List<CollectionItem> _loans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _loans = await _loanService.fetchActiveLoans();
    } catch (_) {
      _loans = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _returnLoan(CollectionItem item) async {
    final confirm = await showDialog<bool>(
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
    if (confirm != true || !mounted) return;

    try {
      await _loanService.returnItem(item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prêt clôturé')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  String _formatLoanDate(CollectionItem item) {
    final at = item.loanedAt;
    if (at == null) return '';
    final d = at.toLocal();
    return 'depuis le ${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes prêts'),
      ),
      drawer: const MainDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loans.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _loans.length,
                    itemBuilder: (context, index) {
                      final item = _loans[index];
                      return Card(
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: item.imageUrl != null
                                  ? BggNetworkImage(url: item.imageUrl!)
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
                          title: Text(item.title),
                          subtitle: Text(
                            [
                              '→ ${item.loaneeDisplayName}',
                              item.category.label,
                              _formatLoanDate(item),
                            ].where((s) => s.isNotEmpty).join(' · '),
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.undo),
                            tooltip: 'Marquer comme rendu',
                            onPressed: () => _returnLoan(item),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) =>
                                  ItemDetailScreen(item: item),
                            ),
                          ).then((_) => _load()),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.handshake_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Aucun prêt en cours',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Depuis la fiche d\'un objet, utilise « Prêter » pour suivre '
              'qui a ton manga, ton jeu, etc.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
