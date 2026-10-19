import 'dart:math';

import 'package:flutter/foundation.dart';
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
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        final path = Uri.base.path;
        final prefix = path.contains('/CollectionApp/')
            ? '/CollectionApp'
            : '';
        return '${Uri.base.origin}$prefix';
      }
    }
    return 'https://kiguelury.github.io/CollectionApp';
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

  String buildUrl(String token, {String show = 'all'}) {
    final scope = show == 'owned' ? '&show=owned' : '';
    return '$baseUrl/showcase.html?t=$token$scope';
  }

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

  Future<ShareExportResult> copyLink({String show = 'all'}) async {
    final settings = await fetchSettings();
    if (!settings.hasLink) {
      final enabled = await setPublic(true);
      if (!enabled.hasLink) {
        throw Exception('Impossible de créer le lien');
      }
      return _copyUrl(enabled.token!, show: show);
    }
    return _copyUrl(settings.token!, show: show);
  }

  Future<ShareExportResult> shareLink({String show = 'all'}) async {
    var settings = await fetchSettings();
    if (!settings.hasLink) {
      settings = await setPublic(true);
    }
    final url = buildUrl(settings.token!, show: show);
    final intro = show == 'owned'
        ? 'Voici ma collection :'
        : 'Voici ma collection (ce que j\'ai + ma wishlist) :';
    final text = '$intro\n$url';

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

  Future<ShareExportResult> _copyUrl(String token, {String show = 'all'}) async {
    final url = buildUrl(token, show: show);
    await Clipboard.setData(ClipboardData(text: url));
    return ShareExportResult(
      kind: ShareExportKind.copiedToClipboard,
      message: 'Lien copié',
    );
  }

  String _newToken() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
