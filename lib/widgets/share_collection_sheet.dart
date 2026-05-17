import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/collection_export_service.dart';
import '../services/collection_share_service.dart';
import '../services/showcase_service.dart';

/// Options pour partager sa collection (amis sans app, CSV assurance).
Future<void> showShareCollectionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => const _ShareCollectionSheet(),
  );
}

class _ShareCollectionSheet extends StatefulWidget {
  const _ShareCollectionSheet();

  @override
  State<_ShareCollectionSheet> createState() => _ShareCollectionSheetState();
}

class _ShareCollectionSheetState extends State<_ShareCollectionSheet> {
  final _share = CollectionShareService();
  final _export = CollectionExportService();
  final _showcase = ShowcaseService();

  ShowcaseSettings? _showcaseSettings;
  bool _loadingShowcase = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadShowcase();
  }

  Future<void> _loadShowcase() async {
    try {
      final s = await _showcase.fetchSettings();
      if (mounted) {
        setState(() {
          _showcaseSettings = s;
          _loadingShowcase = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingShowcase = false);
    }
  }

  Future<void> _run(
    Future<ShareExportResult> Function() action, {
    bool popSheet = true,
  }) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      if (popSheet) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible : $e')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleShowcase(bool enabled) async {
    setState(() => _busy = true);
    try {
      final s = await _showcase.setPublic(enabled);
      if (mounted) {
        setState(() => _showcaseSettings = s);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Vitrine publique activée'
                  : 'Vitrine publique désactivée',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openShowcaseInBrowser() async {
    final token = _showcaseSettings?.token;
    if (token == null) return;
    final uri = Uri.parse(_showcase.buildUrl(token));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = _showcaseSettings?.hasLink ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Partager ma collection',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Pour tes proches sans l\'app : lien web ou résumé par message. '
                'Le CSV reste pour l\'assurance.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              secondary: const Icon(Icons.public),
              title: const Text('Vitrine publique (lien web)'),
              subtitle: Text(
                _loadingShowcase
                    ? 'Chargement…'
                    : hasLink
                        ? 'Page lisible dans le navigateur, sans installer l\'app'
                        : 'Active pour obtenir un lien à envoyer',
              ),
              value: hasLink,
              onChanged: _busy || _loadingShowcase ? null : _toggleShowcase,
            ),
            if (hasLink) ...[
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Copier le lien public'),
                enabled: !_busy,
                onTap: _busy
                    ? null
                    : () => _run(_showcase.copyLink, popSheet: false),
              ),
              ListTile(
                leading: const Icon(Icons.send),
                title: const Text('Envoyer le lien'),
                subtitle: const Text('WhatsApp, mail…'),
                enabled: !_busy,
                onTap: _busy ? null : () => _run(_showcase.shareLink),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: const Text('Ouvrir dans le navigateur'),
                enabled: !_busy,
                onTap: _busy ? null : _openShowcaseInBrowser,
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Résumé texte'),
              subtitle: const Text('Ce que j\'ai + wishlist, sans lien'),
              enabled: !_busy,
              onTap: _busy ? null : () => _run(_share.shareText),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Copier le résumé'),
              enabled: !_busy,
              onTap: _busy ? null : () => _run(_share.copyTextToClipboard),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Page HTML (fichier)'),
              subtitle: const Text('Pièce jointe ou enregistrer sur PC'),
              enabled: !_busy,
              onTap: _busy ? null : () => _run(_share.shareHtml),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Export CSV'),
              subtitle: const Text('Assurance, Excel'),
              enabled: !_busy,
              onTap: _busy ? null : () => _run(_export.shareCsv),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
