import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Benchmark quote source parsing regex performance', () {
    final sampleSources = List<String>.generate(10000, (i) {
      final type = i % 4;
      switch (type) {
        case 0:
          return '作者$i《作品$i》';
        case 1:
          return '《作品$i》作者$i';
        case 2:
          return '作者$i - 作品$i';
        default:
          return '纯文本来源 $i';
      }
    });

    // Baseline implementation matching un-hoisted code
    final stopwatchBaseline = Stopwatch()..start();
    for (final source in sampleSources) {
      String? sourceAuthor;
      String? sourceWork;
      if (source.contains('《') && source.contains('》')) {
        final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
        if (workMatch != null) {
          sourceWork = workMatch.group(1);
          sourceAuthor = source.replaceAll(RegExp(r'《.+?》'), '').trim();
          if (sourceAuthor.isEmpty) {
            sourceAuthor = null;
          }
        }
      } else if (source.contains(' - ')) {
        final parts = source.split(' - ');
        if (parts.length >= 2) {
          sourceAuthor = parts.first.trim();
          sourceWork = parts.sublist(1).join(' - ').trim();
        }
      } else {
        sourceAuthor = source.trim();
      }
      expect(sourceWork != null || sourceAuthor != null, isTrue);
    }
    stopwatchBaseline.stop();

    // Optimized implementation matching hoisted code
    final sourceWorkRegex = RegExp(r'《(.+?)》');
    final sourceWorkStripRegex = RegExp(r'《.+?》');

    final stopwatchOptimized = Stopwatch()..start();
    for (final source in sampleSources) {
      String? sourceAuthor;
      String? sourceWork;
      if (source.contains('《') && source.contains('》')) {
        final workMatch = sourceWorkRegex.firstMatch(source);
        if (workMatch != null) {
          sourceWork = workMatch.group(1);
          sourceAuthor = source.replaceAll(sourceWorkStripRegex, '').trim();
          if (sourceAuthor.isEmpty) {
            sourceAuthor = null;
          }
        }
      } else if (source.contains(' - ')) {
        final parts = source.split(' - ');
        if (parts.length >= 2) {
          sourceAuthor = parts.first.trim();
          sourceWork = parts.sublist(1).join(' - ').trim();
        }
      } else {
        sourceAuthor = source.trim();
      }
      expect(sourceWork != null || sourceAuthor != null, isTrue);
    }
    stopwatchOptimized.stop();

    final baselineUs = stopwatchBaseline.elapsedMicroseconds;
    final optimizedUs = stopwatchOptimized.elapsedMicroseconds;
    final speedupPercent =
        ((baselineUs - optimizedUs) / baselineUs * 100).toStringAsFixed(2);

    print(
        'Baseline execution time (10,000 items): $baselineUs us (${stopwatchBaseline.elapsedMilliseconds} ms)');
    print(
        'Optimized execution time (10,000 items): $optimizedUs us (${stopwatchOptimized.elapsedMilliseconds} ms)');
    print('Performance improvement: $speedupPercent% speedup');
  });
}
