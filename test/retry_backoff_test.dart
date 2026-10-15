import 'package:collection_app/utils/retry_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackoffPolicy.delayFor', () {
    const policy = BackoffPolicy(
      initialDelay: Duration(milliseconds: 500),
      factor: 2,
      maxDelay: Duration(seconds: 3),
      jitter: 0,
    );

    test('croissance exponentielle', () {
      expect(policy.delayFor(0), const Duration(milliseconds: 500));
      expect(policy.delayFor(1), const Duration(milliseconds: 1000));
      expect(policy.delayFor(2), const Duration(milliseconds: 2000));
    });

    test('plafonnée à maxDelay', () {
      expect(policy.delayFor(3), const Duration(seconds: 3));
      expect(policy.delayFor(10), const Duration(seconds: 3));
    });

    test('gigue bornée autour de la valeur nominale', () {
      const jittered = BackoffPolicy(
        initialDelay: Duration(milliseconds: 1000),
        jitter: 0.2,
      );
      for (var i = 0; i < 50; i++) {
        final ms = jittered.delayFor(0).inMilliseconds;
        expect(ms, inInclusiveRange(800, 1200));
      }
    });
  });

  group('retryWithBackoff', () {
    test('réessaie sur 429 puis réussit', () async {
      final statuses = [429, 429, 200];
      final sleeps = <Duration>[];
      var calls = 0;
      final result = await retryWithBackoff<int>(
        (_) async => statuses[calls++],
        shouldRetry: isRetryableHttpStatus,
        policy: const BackoffPolicy(
          initialDelay: Duration(milliseconds: 100),
          jitter: 0,
        ),
        sleep: (d) async => sleeps.add(d),
      );
      expect(result, 200);
      expect(calls, 3);
      expect(sleeps, const [
        Duration(milliseconds: 100),
        Duration(milliseconds: 200),
      ]);
    });

    test('abandonne après maxAttempts et renvoie le dernier résultat', () async {
      var calls = 0;
      final sleeps = <Duration>[];
      final result = await retryWithBackoff<int>(
        (_) async {
          calls++;
          return 429;
        },
        shouldRetry: isRetryableHttpStatus,
        policy: const BackoffPolicy(maxAttempts: 3, jitter: 0),
        sleep: (d) async => sleeps.add(d),
      );
      expect(result, 429);
      expect(calls, 3);
      expect(sleeps.length, 2);
    });

    test('pas de retry sur une réponse définitive', () async {
      var calls = 0;
      await retryWithBackoff<int>(
        (_) async {
          calls++;
          return 404;
        },
        shouldRetry: isRetryableHttpStatus,
        sleep: (_) async {},
      );
      expect(calls, 1);
    });

    test('onRetry reçoit le numéro de tentative', () async {
      final attempts = <int>[];
      var calls = 0;
      await retryWithBackoff<int>(
        (_) async => calls++ < 2 ? 503 : 200,
        shouldRetry: isRetryableHttpStatus,
        sleep: (_) async {},
        onRetry: (a, _) => attempts.add(a),
      );
      expect(attempts, [1, 2]);
    });
  });

  group('Détection rate-limit', () {
    test('statuts HTTP réessayables', () {
      expect(isRetryableHttpStatus(429), isTrue);
      expect(isRetryableHttpStatus(503), isTrue);
      expect(isRetryableHttpStatus(200), isFalse);
      expect(isRetryableHttpStatus(404), isFalse);
    });

    test('corps JSON du proxy relayant un 429', () {
      expect(isRateLimitedJsonBody('{"error":"BGG 429"}'), isTrue);
      expect(isRateLimitedJsonBody('{"error":"Too Many Requests"}'), isTrue);
      expect(isRateLimitedJsonBody('{"error":"not found"}'), isFalse);
      expect(isRateLimitedJsonBody('{"items":[429]}'), isFalse);
      expect(isRateLimitedJsonBody(''), isFalse);
    });
  });
}
