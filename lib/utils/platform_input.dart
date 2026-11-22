import 'package:flutter/foundation.dart';

/// Navigateur mobile (Android / iOS) : le clavier virtuel ne s'ouvre que sur
/// un geste utilisateur. Un autofocus y donne le focus sans clavier, et le
/// 1er tap sur le champ (déjà focalisé) ne fait alors rien.
bool get isMobileWeb =>
    kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Valeur à passer à `autofocus:` des champs texte.
bool get kSafeAutofocus => !isMobileWeb;
