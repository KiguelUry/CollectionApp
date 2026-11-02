import 'package:flutter/foundation.dart';

/// En-têtes communs pour les APIs catalogue.
/// Sur le web (`kIsWeb`), **jamais** de `User-Agent` : c'est un header restreint
/// qui force un preflight CORS (Firefox bloque catalog-proxy).
Map<String, String> get catalogHttpHeaders {
  final headers = <String, String>{'Accept': 'application/json'};
  if (!kIsWeb) {
    headers['User-Agent'] =
        'Collectingo/1.1 (+https://github.com/KiguelUry/CollectionApp; catalog-search)';
  }
  return headers;
}

/// Ajoute `User-Agent` uniquement hors web.
void putNativeUserAgent(Map<String, String> headers, String userAgent) {
  if (!kIsWeb) headers['User-Agent'] = userAgent;
}
