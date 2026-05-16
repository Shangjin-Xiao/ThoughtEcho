import 'dart:collection';
import 'package:benchmark_harness/benchmark_harness.dart';

class _ControllerCacheKey {
  final String quoteId;
  final bool isList;
  final double width;

  const _ControllerCacheKey(this.quoteId, this.isList, this.width);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ControllerCacheKey &&
          runtimeType == other.runtimeType &&
          quoteId == other.quoteId &&
          isList == other.isList &&
          width == other.width;

  @override
  int get hashCode => quoteId.hashCode ^ isList.hashCode ^ width.hashCode;
}

class CacheDeletionBenchmark extends BenchmarkBase {
  final int totalCacheItems;
  final int idsToDelete;
  LinkedHashMap<_ControllerCacheKey, int> _cache =
      LinkedHashMap<_ControllerCacheKey, int>();
  List<String> _targetDeletedIds = [];

  CacheDeletionBenchmark(this.totalCacheItems, this.idsToDelete, String name)
      : super(name);

  @override
  void setup() {
    _cache.clear();
    _targetDeletedIds.clear();
    for (int i = 0; i < totalCacheItems; i++) {
      _cache[_ControllerCacheKey('quote_$i', true, 100.0)] = i;
    }
    for (int i = 0; i < idsToDelete; i++) {
      _targetDeletedIds.add('quote_${i * 2}'); // Delete every other item
    }
  }
}

class LoopCacheDeletionBenchmark extends CacheDeletionBenchmark {
  LoopCacheDeletionBenchmark(int totalCacheItems, int idsToDelete)
      : super(totalCacheItems, idsToDelete,
            "LoopCacheDeletion ($totalCacheItems items, $idsToDelete deletions)");

  @override
  void run() {
    // Simulated O(N*M) loop approach from original code
    for (final quoteId in _targetDeletedIds) {
      final keysToRemove =
          _cache.keys.where((key) => key.quoteId == quoteId).toList();
      for (final key in keysToRemove) {
        _cache.remove(key);
      }
    }
  }
}

class SetCacheDeletionBenchmark extends CacheDeletionBenchmark {
  SetCacheDeletionBenchmark(int totalCacheItems, int idsToDelete)
      : super(totalCacheItems, idsToDelete,
            "SetCacheDeletion ($totalCacheItems items, $idsToDelete deletions)");

  @override
  void run() {
    // Proposed optimized approach
    final idSet = _targetDeletedIds.toSet();
    final keysToRemove =
        _cache.keys.where((key) => idSet.contains(key.quoteId)).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }
}

void main() {
  print('Running Quote Content Cache Deletion Benchmarks...');

  LoopCacheDeletionBenchmark(1000, 500).report();
  SetCacheDeletionBenchmark(1000, 500).report();

  LoopCacheDeletionBenchmark(5000, 1000).report();
  SetCacheDeletionBenchmark(5000, 1000).report();
}
