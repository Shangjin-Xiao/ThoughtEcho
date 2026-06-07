import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import 'package:mockito/mockito.dart';

class MockSettingsService extends Mock implements SettingsService {
  @override
  bool get prioritizeBoldContentInCollapse => true;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

void main() {
  tearDown(() {
    QuoteContent.resetCaches();
  });

  test('QuoteContent Isolate prewarming populates document cache', () async {
    // 构造极端的Delta内容 (伪造一个长文档)
    final ops = [];
    for (int i = 0; i < 500; i++) {
      ops.add({'insert': '大量文本数据 $i '});
      if (i % 10 == 0) ops.add({'insert': '\n', 'attributes': {'bold': true}});
    }
    ops.add({'insert': '\n'});
    final heavyDelta = jsonEncode(ops);

    final List<Quote> quotes = List.generate(10, (index) => Quote(
      id: 'quote_$index',
      content: '纯文本预览',
      deltaContent: heavyDelta,
      editSource: 'fullscreen',
      date: DateTime.now().toIso8601String(),
    ));

    final stopwatch = Stopwatch()..start();
    await QuoteContent.prewarmDocumentsInIsolate(quotes, prioritizeBoldContent: true);
    stopwatch.stop();

    debugPrint('Isolate prewarming 10 heavy documents took: ${stopwatch.elapsedMilliseconds} ms');

    // 验证缓存已被填充
    final stats = QuoteContent.debugCacheStats();
    final docStats = stats['document'] as Map<String, dynamic>;
    
    expect(docStats['cacheSize'], greaterThanOrEqualTo(1));
  });
}
