import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding 30 s (1er lancement), skippable.
class OnboardingService {
  OnboardingService._();
  static final instance = OnboardingService._();

  static const _completedKey = 'onboarding_v1_completed';

  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }

  Future<void> resetForTests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completedKey);
  }
}
