import 'package:flutter/services.dart';

/// Retours haptiques légers (mobile).
abstract final class AppHaptics {
  static void lightTap() {
    HapticFeedback.lightImpact();
  }

  static void selection() {
    HapticFeedback.selectionClick();
  }

  static void success() {
    HapticFeedback.mediumImpact();
  }
}
