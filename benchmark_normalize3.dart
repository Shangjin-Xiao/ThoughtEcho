import 'dart:io';
import 'package:path/path.dart' as path;

Future<String> _normalizeFilePath(
  String filePath, {
  String? cachedAppPath,
}) async {
  // Simulate some async I/O wait which is typical for real-world scenarios
  // In the actual code, _normalizeFilePath itself doesn't have much async wait,
  // but it's an async function and is awaited in a nested loop.
  // We'll use Future.microtask to better simulate the Dart event loop overhead
  await Future.microtask(() {});

  try {
    if (filePath.isEmpty) {
      return filePath;
    }

    var sanitized = filePath.trim();

    if (sanitized.startsWith('file://')) {
      final uri = Uri.tryParse(sanitized);
      if (uri != null && uri.scheme == 'file') {
        sanitized = uri.toFilePath();
      }
    }

    sanitized = path.normalize(sanitized);

    final appPath = cachedAppPath ?? '/data/user/0/com.example.app/app_flutter';

    if (sanitized.startsWith(appPath)) {
      return path.normalize(path.relative(sanitized, from: appPath));
    }

    return sanitized;
  } catch (_) {
    return filePath;
  }
}

void main() async {
  final missingIndex = <String, Map<String, Set<String>>>{};
  // Use a smaller dataset with more duplicate paths to simulate real-world where
  // the same files are referenced multiple times
  for (int i = 0; i < 5000; i++) {
    // 5 variants per item, pointing to a smaller pool of 500 actual files
    final fileIdx = i % 500;
    missingIndex['key_$i'] = {
      '/app/images/img_$fileIdx.jpg': {'q1', 'q2', 'q3'},
      '/app/images/img_${fileIdx}_thumb.jpg': {'q1', 'q4'},
    };
  }

  final appPath = '/app';

  // Warmup
  for (int i = 0; i < 100; i++) {
    await _normalizeFilePath('/app/images/img_$i.jpg', cachedAppPath: appPath);
  }

  // Baseline: Sequential await in nested loops
  final sw = Stopwatch()..start();
  int count = 0;
  for (final variants in missingIndex.values) {
    for (final entry in variants.entries) {
      final filePath = entry.key;
      final normalizedPath = await _normalizeFilePath(
        filePath,
        cachedAppPath: appPath,
      );
      count += entry.value.length;
    }
  }
  sw.stop();
  final baselineMs = sw.elapsedMilliseconds;
  print('Baseline time: $baselineMs ms for $count item iterations');

  // Optimized Cache Approach
  final sw2 = Stopwatch()..start();
  final pathCache = <String, String>{};
  int count2 = 0;

  for (final variants in missingIndex.values) {
    for (final entry in variants.entries) {
      final filePath = entry.key;

      String? normalizedPath = pathCache[filePath];
      if (normalizedPath == null) {
        normalizedPath = await _normalizeFilePath(
          filePath,
          cachedAppPath: appPath,
        );
        pathCache[filePath] = normalizedPath;
      }

      count2 += entry.value.length;
    }
  }
  sw2.stop();
  final optimizedMs = sw2.elapsedMilliseconds;
  print('Optimized cache time: $optimizedMs ms');

  // Optimized: Cache + Future.wait to parallelize path normalization
  final sw3 = Stopwatch()..start();

  // Extract all unique paths first
  final uniquePaths = <String>{};
  for (final variants in missingIndex.values) {
    uniquePaths.addAll(variants.keys);
  }

  // Process all unique paths concurrently
  final pathsList = uniquePaths.toList(growable: false);
  final normalizedList = await Future.wait(
    pathsList.map((p) => _normalizeFilePath(p, cachedAppPath: appPath))
  );

  // Map back to dictionary
  final normalizedPathMap = Map<String, String>.fromIterables(pathsList, normalizedList);

  int count3 = 0;
  // Second pass is purely synchronous
  for (final variants in missingIndex.values) {
    for (final entry in variants.entries) {
      final filePath = entry.key;
      final normalizedPath = normalizedPathMap[filePath]!;
      count3 += entry.value.length;
    }
  }
  sw3.stop();
  final optimizedFutureMs = sw3.elapsedMilliseconds;
  print('Optimized Future.wait time: $optimizedFutureMs ms');

  if (baselineMs > 0) {
    print('Cache Improvement: ${((baselineMs - optimizedMs) / baselineMs * 100).toStringAsFixed(2)}%');
    print('Future.wait Improvement: ${((baselineMs - optimizedFutureMs) / baselineMs * 100).toStringAsFixed(2)}%');
  }
}
