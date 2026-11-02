import 'package:flutter/foundation.dart';

/// En-têtes TCG / Scryfall — sans `User-Agent` sur le web (CORS Firefox).
Map<String, String> get tcgHttpHeaders {
  final headers = <String, String>{'Accept': 'application/json'};
  if (!kIsWeb) {
    headers['User-Agent'] =
        'Collectingo/1.1 (+https://github.com/collectingo/collection-app)';
  }
  return headers;
}
