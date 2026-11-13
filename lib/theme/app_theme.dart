import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'card_skins.dart';

/// Thème global de l'application.
abstract final class AppTheme {
  /// Encre / ardoise : plus de teinte mauve dans les contrôles.
  static const Color seed = Color(0xFF3A4150);
  static const Color ink = Color(0xFF1A1C1F);
  static const Color slate = Color(0xFF5C6570);
  static const Color mist = Color(0xFFE6E8EC);
  static const Color paper = Color(0xFFF4F5F7);
  static const Color surfaceTint = paper;

  /// Fond / icône des placeholders d'image manquante (tuiles, modales).
  static const Color coverPlaceholderBg = Color(0xFFEEEEEE);
  static const Color coverPlaceholderIcon = Color(0xFF9E9E9E);

  /// Accent note BGG (étoiles /5).
  static const Color bggRatingAmber = Color(0xFFFFA000);

  static TextTheme _textTheme(TextTheme base, Color onSurface) {
    return GoogleFonts.plusJakartaSansTextTheme(base).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
  }

  static ThemeData withCardSkin(
    ThemeData base, {
    required CardSkin skin,
    required Color background,
    required bool dark,
  }) {
    final cardColor = skin.fill.first;
    return base.copyWith(
      scaffoldBackgroundColor: dark ? background : base.scaffoldBackgroundColor,
      extensions: [PlayCardStyle(skin)],
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: skin.edge, width: 1.3),
        ),
        margin: EdgeInsets.zero,
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: dark ? skin.accent : base.colorScheme.primary,
        surface: dark ? background : base.colorScheme.surface,
      ),
    );
  }

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: paper,
      primary: ink,
      onPrimary: Colors.white,
      secondary: slate,
      onSecondary: Colors.white,
      primaryContainer: mist,
      onPrimaryContainer: ink,
      secondaryContainer: const Color(0xFFD5D8DE),
      onSecondaryContainer: ink,
      surfaceTint: Colors.transparent,
    );

    final textTheme = _textTheme(ThemeData.light().textTheme, scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: surfaceTint,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      snackBarTheme: _snackBarTheme,
      switchTheme: _switchTheme(scheme),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      segmentedButtonTheme: _segmentedTheme(scheme),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static SwitchThemeData _switchTheme(ColorScheme scheme) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.onPrimary;
        return scheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return scheme.surfaceContainerHighest;
      }),
    );
  }

  static SegmentedButtonThemeData _segmentedTheme(ColorScheme scheme) {
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primaryContainer;
          }
          return scheme.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimaryContainer;
          }
          return scheme.onSurface;
        }),
      ),
    );
  }

  static const SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Color(0xFF1E293B),
    elevation: 6,
    insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      side: BorderSide(color: Color(0xFF10B981)),
    ),
    contentTextStyle: TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
    ),
  );

  static ThemeData get dark {
    const midnight = Color(0xFF121212);
    const deepBlack = scaffoldBlack;

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: midnight,
    ).copyWith(
      primary: const Color(0xFFE8EAED),
      onPrimary: ink,
      secondary: const Color(0xFFB0B6C0),
      onSecondary: ink,
      primaryContainer: const Color(0xFF2C3138),
      onPrimaryContainer: const Color(0xFFF2F3F5),
      secondaryContainer: const Color(0xFF3A4048),
      onSecondaryContainer: const Color(0xFFF2F3F5),
      surface: midnight,
      surfaceTint: Colors.transparent,
      surfaceContainerLow: const Color(0xFF1A1A1F),
      surfaceContainerHigh: const Color(0xFF242429),
      outlineVariant: const Color(0xFF3A3A42),
    );

    final textTheme = _textTheme(ThemeData.dark().textTheme, scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: deepBlack,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      snackBarTheme: _snackBarTheme,
      switchTheme: _switchTheme(scheme),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      segmentedButtonTheme: _segmentedTheme(scheme),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static BoxDecoration heroGradient(Color accent, {Brightness? brightness}) {
    final isDark = brightness == Brightness.dark;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                accent.withValues(alpha: 0.28),
                const Color(0xFF121212),
              ]
            : [
                accent.withValues(alpha: 0.12),
                surfaceTint,
              ],
      ),
    );
  }

  /// Liseré accent catégorie (mode sombre).
  static BoxDecoration categoryAccentBorder(Color accent, {double radius = 20}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
    );
  }
}
