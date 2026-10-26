import 'package:flutter/foundation.dart';

/// En-têtes communs pour les APIs catalogue (certaines refusent les requêtes anonymes).
const catalogHttpHeaders = {
  'Accept': 'application/json',
  'User-Agent':
      'Collectingo/1.1 (+https://github.com/KiguelUry/CollectionApp; catalog-search)',
};

/// Sur le web, iTunes bloque CORS → proxy public.
Uri catalogProxiedUri(Uri target) {
  if (!kIsWeb) return target;
  final encoded = Uri.encodeComponent(target.toString());
  return Uri.parse('https://corsproxy.io/?url=$encoded');
}
