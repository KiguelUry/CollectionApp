/// Cache mémoire générique TTL + dédoublonnage in-flight (lectures Supabase).
class SupabaseReadCache {
  SupabaseReadCache._();

  static const defaultTtl = Duration(minutes: 10);

  static final Map<String, _Entry> _entries = {};
  static final Map<String, Future<dynamic>> _inFlight = {};

  static void invalidate([String? keyPrefix]) {
    if (keyPrefix == null || keyPrefix.isEmpty) {
      _entries.clear();
      _inFlight.clear();
      return;
    }
    _entries.removeWhere((k, _) => k.startsWith(keyPrefix));
    _inFlight.removeWhere((k, _) => k.startsWith(keyPrefix));
  }

  static Future<T> getOrFetch<T>({
    required String key,
    required Future<T> Function() loader,
    Duration ttl = defaultTtl,
    bool force = false,
  }) async {
    if (!force) {
      final hit = _entries[key];
      if (hit != null &&
          hit.value is T &&
          DateTime.now().difference(hit.at) < ttl) {
        return hit.value as T;
      }
      final pending = _inFlight[key];
      if (pending != null) return await pending as T;
    }

    final future = loader();
    _inFlight[key] = future;
    try {
      final value = await future;
      _entries[key] = _Entry(value, DateTime.now());
      return value;
    } finally {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }
  }
}

class _Entry {
  final Object? value;
  final DateTime at;
  _Entry(this.value, this.at);
}
