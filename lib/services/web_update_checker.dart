import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'web_update_platform.dart';

/// Surveille `version.json` (généré au deploy) et propose un reload propre.
class WebUpdateChecker {
  WebUpdateChecker._();
  static final instance = WebUpdateChecker._();

  String? _bootVersion;
  OverlayEntry? _banner;
  bool _checking = false;
  bool _started = false;

  Future<void> start(BuildContext context) async {
    if (!kIsWeb || _started) return;
    _started = true;
    _bootVersion ??= await _fetchVersion();
    bindVisibilityChange(() {
      if (context.mounted) unawaited(check(context));
    });
    unawaited(Future<void>.delayed(const Duration(seconds: 2), () {
      if (context.mounted) check(context);
    }));
  }

  void dispose() {
    unbindVisibilityChange();
    _banner?.remove();
    _banner = null;
    _started = false;
  }

  Future<void> check(BuildContext context) async {
    if (!kIsWeb || _checking) return;
    _checking = true;
    try {
      final remote = await _fetchVersion();
      if (remote == null || _bootVersion == null) return;
      if (remote == _bootVersion) return;
      if (!context.mounted) return;
      _showBanner(context);
    } finally {
      _checking = false;
    }
  }

  Future<String?> _fetchVersion() async {
    try {
      final uri = Uri.base.resolve(
        'version.json?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body);
      if (map is Map && map['version'] != null) {
        return map['version'].toString();
      }
    } catch (_) {}
    return null;
  }

  void _showBanner(BuildContext context) {
    if (_banner != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _banner = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 12,
        right: 12,
        bottom: 16,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF1E1E24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '✨ Nouvelle version disponible',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _applyUpdate,
                  child: const Text('Mettre à jour'),
                ),
                IconButton(
                  tooltip: 'Plus tard',
                  onPressed: () {
                    _banner?.remove();
                    _banner = null;
                  },
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(_banner!);
  }

  Future<void> _applyUpdate() async {
    _banner?.remove();
    _banner = null;
    await clearWebCaches();
    reloadPage();
  }
}
