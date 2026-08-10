import 'package:flutter/foundation.dart';

/// URLs de redirection Auth (à autoriser dans Supabase → Authentication → URL Configuration).
abstract final class AuthRedirectConfig {
  /// Site public GitHub Pages (prod web).
  static const webProdOrigin = 'https://kiguelury.github.io';
  static const webProdPath = '/CollectionApp/';
  static const webProdUrl = '$webProdOrigin$webProdPath';

  /// Où renvoyer l’utilisateur après le clic dans l’e-mail de reset.
  ///
  /// - Web : l’origine courante (prod ou localhost).
  /// - Mobile : le site web public (pas de deep link natif configuré).
  static String passwordResetRedirectTo() {
    if (kIsWeb) {
      final base = Uri.base;
      var path = base.path;
      if (path.isEmpty || path == '/') {
        path = '/';
      } else if (!path.endsWith('/')) {
        path = '$path/';
      }
      // Sur GitHub Pages le base-href est /CollectionApp/
      if (base.host.contains('github.io') && !path.startsWith('/CollectionApp')) {
        path = webProdPath;
      }
      return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort && base.port != 80 && base.port != 443
            ? base.port
            : null,
        path: path,
      ).toString();
    }
    return webProdUrl;
  }
}
