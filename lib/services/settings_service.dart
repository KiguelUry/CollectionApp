import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_cache_service.dart';
import 'profile_service.dart';

enum AppThemePreference { system, light, dark }

/// Préférences locales (thème, notifications, confidentialité affichée).
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _keyDarkModeLegacy = 'settings_dark_mode';
  static const _keyThemePreference = 'settings_theme_preference_v2';
  static const _keyNotifications = 'settings_notifications_enabled';
  static const _keyHideFromNonFriends = 'settings_hide_from_non_friends';
  static const _keyHideFromFriends = 'settings_hide_from_friends';
  static const _keyShareWishlist = 'settings_share_wishlist_with_friends';

  SharedPreferences? _prefs;
  bool _loaded = false;

  AppThemePreference themePreference = AppThemePreference.system;
  bool notificationsEnabled = true;
  /// Masquer ma collection aux non-amis (défaut : oui).
  bool hideCollectionFromNonFriends = true;
  /// Masquer ma collection à mes amis (défaut : non).
  bool hideCollectionFromFriends = false;
  /// Wishlist visible par les amis (défaut : oui).
  bool shareWishlistWithFriends = true;

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString(_keyThemePreference);
    if (stored != null) {
      themePreference = AppThemePreference.values.firstWhere(
        (p) => p.name == stored,
        orElse: () => AppThemePreference.system,
      );
    } else if (_prefs!.containsKey(_keyDarkModeLegacy)) {
      final legacyDark = _prefs!.getBool(_keyDarkModeLegacy) ?? false;
      themePreference =
          legacyDark ? AppThemePreference.dark : AppThemePreference.light;
    } else {
      themePreference = AppThemePreference.system;
    }
    notificationsEnabled = _prefs!.getBool(_keyNotifications) ?? true;
    hideCollectionFromNonFriends =
        _prefs!.getBool(_keyHideFromNonFriends) ?? true;
    hideCollectionFromFriends =
        _prefs!.getBool(_keyHideFromFriends) ?? false;
    shareWishlistWithFriends =
        _prefs!.getBool(_keyShareWishlist) ?? true;
    _loaded = true;
    notifyListeners();
    await ProfileCacheService.instance.hydrate();
    _syncPrivacyFromProfile();
  }

  Future<void> _syncPrivacyFromProfile() async {
    try {
      final profile = await ProfileService().fetchCurrentProfile();
      shareWishlistWithFriends = profile.shareWishlist;
      hideCollectionFromNonFriends = profile.hideCollectionFromNonFriends;
      hideCollectionFromFriends = profile.hideCollectionFromFriends;
      await _prefs?.setBool(_keyShareWishlist, shareWishlistWithFriends);
      await _prefs?.setBool(
        _keyHideFromNonFriends,
        hideCollectionFromNonFriends,
      );
      await _prefs?.setBool(_keyHideFromFriends, hideCollectionFromFriends);
      notifyListeners();
    } catch (_) {
      // Colonne absente ou hors ligne : préférence locale conservée
    }
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    themePreference = value;
    await _prefs?.setString(_keyThemePreference, value.name);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    await setThemePreference(
      value ? AppThemePreference.dark : AppThemePreference.light,
    );
  }

  bool get darkMode => themePreference == AppThemePreference.dark;

  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    await _prefs?.setBool(_keyNotifications, value);
    notifyListeners();
  }

  Future<void> setHideFromNonFriends(bool value) async {
    hideCollectionFromNonFriends = value;
    await _prefs?.setBool(_keyHideFromNonFriends, value);
    notifyListeners();
    await _pushCollectionPrivacy();
  }

  Future<void> setHideFromFriends(bool value) async {
    hideCollectionFromFriends = value;
    await _prefs?.setBool(_keyHideFromFriends, value);
    notifyListeners();
    await _pushCollectionPrivacy();
  }

  Future<void> _pushCollectionPrivacy() async {
    try {
      await ProfileService().updateCollectionPrivacy(
        hideFromNonFriends: hideCollectionFromNonFriends,
        hideFromFriends: hideCollectionFromFriends,
      );
    } catch (_) {
      // Migration SQL non appliquée
    }
  }

  Future<void> setShareWishlistWithFriends(bool value) async {
    shareWishlistWithFriends = value;
    await _prefs?.setBool(_keyShareWishlist, value);
    notifyListeners();
    try {
      await ProfileService().updateShareWishlist(value);
    } catch (_) {
      // Profil non synchronisé (migration SQL à exécuter)
    }
  }

  ThemeMode get themeMode => switch (themePreference) {
        AppThemePreference.dark => ThemeMode.dark,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.system => ThemeMode.system,
      };
}
