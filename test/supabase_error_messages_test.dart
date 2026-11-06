import 'package:collection_app/utils/supabase_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('402 exceed_egress_quota → message humain avec date', () {
    const raw =
        'AuthApiException(message: Service for this project is restricted '
        'due to the following violations: exceed_egress_quota. '
        'The project owner must upgrade their plan or remove spend caps '
        'to restore service., statusCode: 402, code: null)';
    final msg = humanizeSupabaseError(raw);
    expect(msg, contains('quota'));
    expect(msg, contains('10 novembre'));
    expect(msg, isNot(contains('AuthApiException')));
  });

  test('identifiants invalides', () {
    expect(
      humanizeSupabaseError('AuthApiException(message: Invalid login credentials)'),
      'E-mail ou mot de passe incorrect.',
    );
  });
}
