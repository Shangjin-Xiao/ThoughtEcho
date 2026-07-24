import 'package:path/path.dart' as path;

Future<String> _normalizeFilePath(
  String filePath, {
  String? cachedAppPath,
}) async {
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
  for (int i = 0; i < 10000; i++) {
    missingIndex['key_$i'] = {
      '/data/user/0/com.example.app/app_flutter/images/img_$i.jpg': {'quote_1', 'quote_2'},
      '/data/user/0/com.example.app/app_flutter/images/img_${i}_thumb.jpg': {'quote_1'},
    };
  }

  final appPath = '/data/user/0/com.example.app/app_flutter';

  // Warmup
  for (int i = 0; i < 1000; i++) {
    await _normalizeFilePath('/data/user/0/com.example.app/app_flutter/images/img_$i.jpg', cachedAppPath: appPath);
  }

  // Baseline
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
  print('Baseline time: $baselineMs ms for $count items');

  // Optimized
  final sw2 = Stopwatch()..start();
  final uniquePaths = <String>{};
  for (final variants in missingIndex.values) {
    uniquePaths.addAll(variants.keys);
  }
  final pathsList = uniquePaths.toList(growable: false);
  final normalizedList = await Future.wait(
    pathsList.map((p) => _normalizeFilePath(p, cachedAppPath: appPath)),
  );
  final normalizedPathMap = Map<String, String>.fromIterables(pathsList, normalizedList);

  int count2 = 0;
  for (final variants in missingIndex.values) {
    for (final entry in variants.entries) {
      final filePath = entry.key;
      final normalizedPath = normalizedPathMap[filePath]!;
      count2 += entry.value.length;
    }
  }
  sw2.stop();
  final optimizedMs = sw2.elapsedMilliseconds;
  print('Optimized time: $optimizedMs ms for $count2 items');

  if (baselineMs > 0) {
    print('Improvement: ${((baselineMs - optimizedMs) / baselineMs * 100).toStringAsFixed(2)}%');
  }
}
