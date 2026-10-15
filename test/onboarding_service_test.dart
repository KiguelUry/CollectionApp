import 'package:collection_app/services/onboarding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('marque l\'onboarding comme terminé', () async {
    final svc = OnboardingService.instance;
    expect(await svc.isCompleted(), isFalse);
    await svc.markCompleted();
    expect(await svc.isCompleted(), isTrue);
    await svc.resetForTests();
    expect(await svc.isCompleted(), isFalse);
  });
}
