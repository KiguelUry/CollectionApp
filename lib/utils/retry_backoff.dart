import 'dart:math';

/// Backoff exponentiel plafonné (avec gigue optionnelle) pour les API limitées.
class BackoffPolicy {
  final Duration initialDelay;
  final double factor;
  final Duration maxDelay;
  final int maxAttempts;
  final double jitter;

  const BackoffPolicy({
    this.initialDelay = const Duration(milliseconds: 800),
    this.factor = 2,
    this.maxDelay = const Duration(seconds: 12),
    this.maxAttempts = 5,
    this.jitter = 0.2,
  });

  /// Délai avant la tentative [retryIndex] + 1 (0 = premier retry).
  Duration delayFor(int retryIndex, {Random? random}) {
    final base = initialDelay.inMilliseconds * pow(factor, retryIndex);
    final capped = min(base.toDouble(), maxDelay.inMilliseconds.toDouble());
    if (jitter <= 0) return Duration(milliseconds: capped.round());
    final rng = random ?? Random();
    final spread = capped * jitter;
    final withJitter = capped - spread + rng.nextDouble() * spread * 2;
    return Duration(
      milliseconds: min(withJitter, maxDelay.inMilliseconds.toDouble()).round(),
    );
  }
}

typedef BackoffSleep = Future<void> Function(Duration delay);

Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);

/// Exécute [action] et réessaie tant que [shouldRetry] renvoie vrai.
///
/// Retourne le dernier résultat obtenu (même s'il demande encore un retry)
/// une fois [BackoffPolicy.maxAttempts] atteint.
Future<T> retryWithBackoff<T>(
  Future<T> Function(int attempt) action, {
  required bool Function(T result) shouldRetry,
  BackoffPolicy policy = const BackoffPolicy(),
  BackoffSleep sleep = _defaultSleep,
  void Function(int attempt, Duration delay)? onRetry,
  Random? random,
}) async {
  late T result;
  for (var attempt = 0; attempt < policy.maxAttempts; attempt++) {
    result = await action(attempt);
    if (!shouldRetry(result)) return result;
    if (attempt == policy.maxAttempts - 1) break;
    final delay = policy.delayFor(attempt, random: random);
    onRetry?.call(attempt + 1, delay);
    await sleep(delay);
  }
  return result;
}

/// Codes HTTP à réessayer (rate-limit, surcharge, « accepted » BGG).
bool isRetryableHttpStatus(int status) =>
    status == 429 || status == 502 || status == 503 || status == 504;

/// Proxy JSON qui relaie un rate-limit amont dans `{"error": "... 429 ..."}`.
bool isRateLimitedJsonBody(String body) {
  if (body.isEmpty || !body.contains('"error"')) return false;
  final lower = body.toLowerCase();
  return lower.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('too many requests');
}
