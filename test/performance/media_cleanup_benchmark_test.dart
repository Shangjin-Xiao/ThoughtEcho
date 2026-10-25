import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/media_reference_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Benchmark media path extraction across quotes', () async {
    const dummyAppPath = '/data/user/0/com.thoughtecho.app/app_flutter';

    // 生成 5000 条包含富文本媒体引用的 Quote
    final quotes = List.generate(5000, (i) {
      final delta = jsonEncode([
        {'insert': 'Header text $i\n'},
        {
          'insert': {
            'image':
                '/data/user/0/com.thoughtecho.app/app_flutter/media/images/img_$i.jpg'
          }
        },
        {'insert': '\nMiddle text $i\n'},
        {
          'insert': {
            'custom': {
              'audio':
                  '/data/user/0/com.thoughtecho.app/app_flutter/media/audios/aud_$i.mp3'
            }
          }
        },
        {'insert': '\nFooter text $i\n'}
      ]);
      return Quote(
        id: 'quote_$i',
        content: 'Content $i',
        date: '2026-03-30 10:00:00',
        deltaContent: delta,
      );
    });

    final Stopwatch stopwatch = Stopwatch()..start();

    // 模拟批处理路径提取
    const quoteChunkSize = 50;
    int extractedCount = 0;

    for (var i = 0; i < quotes.length; i += quoteChunkSize) {
      final chunk = quotes.sublist(
        i,
        i + quoteChunkSize > quotes.length ? quotes.length : i + quoteChunkSize,
      );

      final chunkResults = await Future.wait(
        chunk.map((quote) async {
          return await MediaReferenceService.extractMediaPathsFromQuote(
            quote,
            cachedAppPath: dummyAppPath,
          );
        }),
      );

      for (final res in chunkResults) {
        extractedCount += res.length;
      }
    }

    stopwatch.stop();

    expect(extractedCount, equals(10000));
    // Print timing result
    // ignore: avoid_print
    print(
      'BENCHMARK_EXTRACT_MEDIA_PATHS: ${quotes.length} quotes, total extracted: $extractedCount, elapsed ms: ${stopwatch.elapsedMilliseconds}',
    );
  });
}
