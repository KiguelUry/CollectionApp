import 'package:collection_app/utils/supabase_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('402 exceed_egress_quota → message sans date ni plan', () {
    const raw =
        'AuthApiException(message: Service for this project is restricted '
        'due to the following violations: exceed_egress_quota. '
        'The project owner must upgrade their plan or remove spend caps '
        'to restore service., statusCode: 402, code: null)';
    final msg = humanizeSupabaseError(raw);
    expect(msg, contains('Service momentanément indisponible'));
    expect(msg, contains('capacité technique maximale'));
    expect(msg, isNot(contains('10 novembre')));
    expect(msg, isNot(contains('AuthApiException')));
  });

  test('adresse e-mail refusée', () {
    expect(
      humanizeSupabaseError(
        'AuthApiException(message: Unable to validate email address, statusCode: 400, code: email_address_invalid)',
      ),
      'Cette adresse e-mail n’est pas valide.',
    );
  });

  test('identifiants invalides', () {
    expect(
      humanizeSupabaseError('AuthApiException(message: Invalid login credentials)'),
      'E-mail ou mot de passe incorrect.',
    );
  });
}
