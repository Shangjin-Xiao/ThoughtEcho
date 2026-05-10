class ExpiringCache<K, V> {
  ExpiringCache({
    required this.expiration,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration expiration;
  final DateTime Function() _now;
  final Map<K, V> _values = {};
  final Map<K, DateTime> _timestamps = {};

  V? operator [](K key) => _values[key];

  void operator []=(K key, V value) {
    _values[key] = value;
    _timestamps[key] = _now();
  }

  void remove(K key) {
    _values.remove(key);
    _timestamps.remove(key);
  }

  int removeExpired() {
    final now = _now();
    final expiredKeys = <K>[];

    for (final entry in _timestamps.entries) {
      if (now.difference(entry.value) > expiration) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      remove(key);
    }

    return expiredKeys.length;
  }

  void clear() {
    _values.clear();
    _timestamps.clear();
  }
}
