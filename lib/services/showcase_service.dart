import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_export_service.dart';

class ShowcaseSettings {
  final bool isPublic;
  final String? token;

  const ShowcaseSettings({required this.isPublic, this.token});

  bool get hasLink => isPublic && token != null && token!.isNotEmpty;
}

/// Lien public vers web/showcase.html (amis sans l'app).
class ShowcaseService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  String get baseUrl {
    final fromEnv = dotenv.env['SHOWCASE_WEB_URL']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv.replaceAll(RegExp(r'/$'), '');
    }
    return 'http://localhost:8080';
  }

  Future<ShowcaseSettings> fetchSettings() async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final row = await _client
        .from('profiles')
        .select('showcase_public, showcase_token')
        .eq('id', id)
        .single();

    return ShowcaseSettings(
      isPublic: row['showcase_public'] as bool? ?? false,
      token: row['showcase_token'] as String?,
    );
  }

  String buildUrl(String token) => '$baseUrl/showcase.html?t=$token';

  Future<ShowcaseSettings> setPublic(bool enabled) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final current = await fetchSettings();
    final token = current.token ?? _newToken();

    final row = await _client
        .from('profiles')
        .update({
          'showcase_public': enabled,
          'showcase_token': token,
        })
        .eq('id', id)
        .select('showcase_public, showcase_token')
        .single();

    return ShowcaseSettings(
      isPublic: row['showcase_public'] as bool? ?? false,
      token: row['showcase_token'] as String?,
    );
  }

  Future<ShowcaseSettings> regenerateToken() async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final token = _newToken();
    final row = await _client
        .from('profiles')
        .update({
          'showcase_token': token,
          'showcase_public': true,
        })
        .eq('id', id)
        .select('showcase_public, showcase_token')
        .single();

    return ShowcaseSettings(
      isPublic: row['showcase_public'] as bool? ?? false,
      token: row['showcase_token'] as String?,
    );
  }

  Future<ShareExportResult> copyLink() async {
    final settings = await fetchSettings();
    if (!settings.hasLink) {
      final enabled = await setPublic(true);
      if (!enabled.hasLink) {
        throw Exception('Impossible de créer le lien');
      }
      return _copyUrl(enabled.token!);
    }
    return _copyUrl(settings.token!);
  }

  Future<ShareExportResult> shareLink() async {
    var settings = await fetchSettings();
    if (!settings.hasLink) {
      settings = await setPublic(true);
    }
    final url = buildUrl(settings.token!);
    final text =
        'Voici ma collection (ce que j\'ai + ma wishlist) :\n$url';

    try {
      await Share.share(text, subject: 'Ma collection');
      return const ShareExportResult(
        kind: ShareExportKind.shared,
        message: 'Lien partagé',
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      return const ShareExportResult(
        kind: ShareExportKind.copiedToClipboard,
        message: 'Lien copié dans le presse-papiers',
      );
    }
  }

  Future<ShareExportResult> _copyUrl(String token) async {
    final url = buildUrl(token);
    await Clipboard.setData(ClipboardData(text: url));
    return ShareExportResult(
      kind: ShareExportKind.copiedToClipboard,
      message: 'Lien copié :\n$url',
    );
  }

  String _newToken() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
