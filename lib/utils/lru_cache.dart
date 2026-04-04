import 'dart:collection';

class LruCache<K, V> {
  final int maxSize;
  final Duration? expiration;
  final LinkedHashMap<K, _CacheEntry<V>> _cache =
      LinkedHashMap<K, _CacheEntry<V>>();

  LruCache({this.maxSize = 100, this.expiration});

  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    final entry = _cache[key]!;
    if (expiration != null) {
      if (DateTime.now().difference(entry.timestamp) > expiration!) {
        _cache.remove(key);
        return null;
      }
    }

    // Move to end (most recently used)
    _cache.remove(key);
    _cache[key] = entry;

    return entry.value;
  }

  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
      // Remove first (least recently used)
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = _CacheEntry<V>(value, DateTime.now());
  }

  void remove(K key) {
    _cache.remove(key);
  }

  void clear() {
    _cache.clear();
  }

  int get length => _cache.length;

  bool containsKey(K key) => _cache.containsKey(key);

  Iterable<K> get keys => _cache.keys;

  void cleanExpired() {
    if (expiration == null) return;

    final now = DateTime.now();
    final expiredKeys = <K>[];

    for (final entry in _cache.entries) {
      if (now.difference(entry.value.timestamp) > expiration!) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _cache.remove(key);
    }
  }
}

class _CacheEntry<V> {
  final V value;
  final DateTime timestamp;

  _CacheEntry(this.value, this.timestamp);
}
