import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Benchmark quote source parsing regex performance', () {
    final sampleSources = List<String>.generate(2000, (i) {
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

    final sourceWorkRegex = RegExp(r'《(.+?)》');
    final sourceWorkStripRegex = RegExp(r'《.+?》');

    (String?, String?) parseBaseline(String source) {
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
      return (sourceAuthor, sourceWork);
    }

    (String?, String?) parseOptimized(String source) {
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
      return (sourceAuthor, sourceWork);
    }

    // 1. 验证基线与优化实现的输出完全一致（防回归断言）
    for (final source in sampleSources) {
      final baseline = parseBaseline(source);
      final optimized = parseOptimized(source);
      expect(optimized.$1, equals(baseline.$1));
      expect(optimized.$2, equals(baseline.$2));
    }

    // 2. 预热运行
    for (int i = 0; i < 200; i++) {
      parseBaseline(sampleSources[i]);
      parseOptimized(sampleSources[i]);
    }

    // 3. 多轮计时比较（不含 expect 断言开销）
    final stopwatchBaseline = Stopwatch()..start();
    for (final source in sampleSources) {
      parseBaseline(source);
    }
    stopwatchBaseline.stop();

    final stopwatchOptimized = Stopwatch()..start();
    for (final source in sampleSources) {
      parseOptimized(source);
    }
    stopwatchOptimized.stop();

    expect(stopwatchOptimized.elapsedMicroseconds,
        lessThanOrEqualTo(stopwatchBaseline.elapsedMicroseconds * 2));
  });
}
