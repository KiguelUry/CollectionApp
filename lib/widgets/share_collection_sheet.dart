import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String _visitorShow = 'all';
  String _preview = '';

  @override
  void initState() {
    super.initState();
    _loadShowcase();
  }

  Future<void> _loadShowcase() async {
    try {
      final s = await _showcase.fetchSettings();
      final prefs = await SharedPreferences.getInstance();
      final show = prefs.getString('showcase_visitor_show') ?? 'all';
      final text = await _share.buildReadableText();
      if (mounted) {
        setState(() {
          _showcaseSettings = s;
          _visitorShow = show == 'owned' ? 'owned' : 'all';
          _preview = text;
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
    final uri = Uri.parse(_showcase.buildUrl(token, show: _visitorShow));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _setVisitorShow(String show) async {
    setState(() => _visitorShow = show);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('showcase_visitor_show', show);
  }

  Widget _bento({
    required Color tint,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      color: tint,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = _showcaseSettings?.hasLink ?? false;
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview.trim().isEmpty
        ? 'Chargement du résumé…'
        : _preview.trim();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Partager ma collection',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              _bento(
                tint: scheme.primaryContainer.withValues(alpha: 0.45),
                children: [
                  const Text(
                    '🌐 Vitrine Web Interactive',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vitrine publique'),
                    subtitle: Text(
                      _loadingShowcase
                          ? 'Chargement…'
                          : 'Page lisible dans le navigateur',
                    ),
                    value: hasLink,
                    onChanged: _busy || _loadingShowcase ? null : _toggleShowcase,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Collection + Wishlist'),
                        selected: _visitorShow == 'all',
                        showCheckmark: false,
                        onSelected: hasLink ? (_) => _setVisitorShow('all') : null,
                      ),
                      ChoiceChip(
                        label: const Text('Collection seule'),
                        selected: _visitorShow == 'owned',
                        showCheckmark: false,
                        onSelected: hasLink
                            ? (_) => _setVisitorShow('owned')
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: !hasLink || _busy
                              ? null
                              : _openShowcaseInBrowser,
                          icon: const Text('👁️'),
                          label: const Text('Aperçu'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: !hasLink || _busy
                              ? null
                              : () => _run(
                                    () => _showcase.copyLink(show: _visitorShow),
                                    popSheet: false,
                                  ),
                          icon: const Text('🔗'),
                          label: const Text('Partager / Copier'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _bento(
                tint: scheme.secondaryContainer.withValues(alpha: 0.55),
                children: [
                  const Text(
                    '💬 Résumé rapide par message',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                    _share.copyTextToClipboard,
                                    popSheet: false,
                                  ),
                          icon: const Text('📋'),
                          label: const Text('Copier le texte'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _run(_share.shareText),
                          icon: const Text('📲'),
                          label: const Text('Envoyer'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _bento(
                tint: scheme.tertiaryContainer.withValues(alpha: 0.55),
                children: [
                  const Text(
                    '📁 Export & Sauvegarde',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Assurance ou copie hors-ligne sur le PC.',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _run(_export.shareCsv),
                          icon: const Text('📊'),
                          label: const Text('Export CSV'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _run(_share.shareHtml),
                          icon: const Text('📄'),
                          label: const Text('HTML hors-ligne'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
