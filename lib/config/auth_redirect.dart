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
      // Le site est servi sous /CollectionApp/. Sans ce chemin, le lien
      // mail atterrit sur kiguelury.github.io/ et GitHub Pages répond 404.
      if (base.host.contains('github.io')) return webProdUrl;
      var path = base.path;
      if (path.isEmpty || path == '/') {
        path = '/';
      } else if (!path.endsWith('/')) {
        path = '$path/';
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
