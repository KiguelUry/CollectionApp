import 'package:collection_app/services/offline_mode.dart';
import 'package:collection_app/services/supabase_capacity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    OfflineMode.instance.setOnline();
    SupabaseCapacity.resetSnackGateForTest();
  });

  test('détecte quota / egress / 429', () {
    expect(
      SupabaseCapacity.looksLikeCapacityError(
        const PostgrestException(message: 'Egress quota exceeded', code: '402'),
      ),
      isTrue,
    );
    expect(
      SupabaseCapacity.looksLikeCapacityError(
        const PostgrestException(message: 'Too Many Requests', code: '429'),
      ),
      isTrue,
    );
    expect(
      SupabaseCapacity.looksLikeCapacityError(
        Exception('Log ingestion limit exceeded'),
      ),
      isTrue,
    );
  });

  test('markDegraded active OfflineMode', () {
    expect(OfflineMode.instance.active, isFalse);
    final ok = SupabaseCapacity.markDegraded(
      Exception('over_capacity: project paused'),
    );
    expect(ok, isTrue);
    expect(OfflineMode.instance.active, isTrue);
  });

  test('erreur banale non-quota : pas de dégradation', () {
    expect(
      SupabaseCapacity.looksLikeCapacityError(
        const PostgrestException(message: 'duplicate key', code: '23505'),
      ),
      isFalse,
    );
  });
}
