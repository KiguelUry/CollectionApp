import 'package:collection_app/utils/network_feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('messages réseau explicites', () {
    expect(
      networkErrorMessage(Exception('SocketException: Failed host lookup')),
      contains('connexion'),
    );
    expect(
      networkErrorMessage(const PostgrestException(message: 'JWT expired', code: 'PGRST301')),
      contains('Session expirée'),
    );
  });
}
