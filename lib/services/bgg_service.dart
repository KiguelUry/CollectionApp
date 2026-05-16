import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class BggService {
  static Map<String, String> get _headers {
    final token = dotenv.env['BGG_APPLICATION_TOKEN'];
    if (token == null || token.isEmpty) {
      throw Exception('Variable BGG_APPLICATION_TOKEN manquante dans .env');
    }
    return {
      'User-Agent': 'Mozilla/5.0 (Android 14; SM-S931B) AppleWebKit/537.36',
      'Accept': 'application/xml',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<List<Map<String, String>>> searchGames(String query) async {
    try {
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/search', {
        'query': query,
        'type': 'boardgame',
      });
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final items = document.findAllElements('item');

        return items.map((node) {
          final title =
              node.findElements('name').first.getAttribute('value') ??
              'Sans titre';
          final id = node.getAttribute('id') ?? '';
          final year =
              node
                  .findElements('yearpublished')
                  .firstOrNull
                  ?.getAttribute('value') ??
              '';
          return {'id': id, 'title': title, 'year': year};
        }).toList();
      }
    } catch (e) {
      debugPrint('Erreur recherche BGG: $e');
    }
    return [];
  }

  // --- AUTOMATISATION : RÉCUPÈRE TOUTES LES INFOS ---
  static Future<Map<String, dynamic>?> getGameFullDetails(String bggId) async {
    try {
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/thing', {
        'id': bggId,
      });
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final item = document.findAllElements('item').first;

        return {
          'image_url':
              item.findAllElements('image').firstOrNull?.innerText ??
              item.findAllElements('thumbnail').firstOrNull?.innerText,
          'min_players': int.tryParse(
            item
                    .findAllElements('minplayers')
                    .firstOrNull
                    ?.getAttribute('value') ??
                '',
          ),
          'max_players': int.tryParse(
            item
                    .findAllElements('maxplayers')
                    .firstOrNull
                    ?.getAttribute('value') ??
                '',
          ),
          'playing_time': int.tryParse(
            item
                    .findAllElements('playingtime')
                    .firstOrNull
                    ?.getAttribute('value') ??
                '',
          ),
        };
      }
    } catch (e) {
      debugPrint('Erreur détails BGG: $e');
    }
    return null;
  }
}
