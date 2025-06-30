/// Unit tests for ClipboardService
import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/clipboard_service.dart';
import '../mocks/mock_clipboard_service.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('ClipboardService Tests', () {
    late MockClipboardService clipboardService;

    setUpAll(() {
      TestHelpers.setupTestEnvironment();
    });

    setUp(() async {
      clipboardService = MockClipboardService();
      await clipboardService.init();
    });

    tearDownAll(() {
      TestHelpers.teardownTestEnvironment();
    });

    group('Initialization', () {
      test('should initialize successfully', () {
        expect(clipboardService.isInitialized, isTrue);
        expect(clipboardService.enableClipboardMonitoring, isFalse);
        expect(clipboardService.isMonitoring, isFalse);
      });

      test('should have empty initial state', () {
        expect(clipboardService.lastProcessedContent, isEmpty);
        expect(clipboardService.currentClipboardContent, isNull);
      });
    });

    group('Monitoring Control', () {
      test('should enable monitoring successfully', () async {
        await clipboardService.enableMonitoring();
        
        expect(clipboardService.enableClipboardMonitoring, isTrue);
        expect(clipboardService.isMonitoring, isTrue);
      });

      test('should disable monitoring successfully', () async {
        await clipboardService.enableMonitoring();
        expect(clipboardService.isMonitoring, isTrue);
        
        await clipboardService.disableMonitoring();
        expect(clipboardService.enableClipboardMonitoring, isFalse);
        expect(clipboardService.isMonitoring, isFalse);
      });

      test('should set monitoring preference', () async {
        await clipboardService.setClipboardMonitoring(true);
        expect(clipboardService.enableClipboardMonitoring, isTrue);
        expect(clipboardService.isMonitoring, isTrue);
        
        await clipboardService.setClipboardMonitoring(false);
        expect(clipboardService.enableClipboardMonitoring, isFalse);
        expect(clipboardService.isMonitoring, isFalse);
      });

      test('should start monitoring convenience method', () async {
        await clipboardService.startMonitoring();
        
        expect(clipboardService.isInitialized, isTrue);
        expect(clipboardService.enableClipboardMonitoring, isTrue);
        expect(clipboardService.isMonitoring, isTrue);
      });

      test('should stop monitoring convenience method', () async {
        await clipboardService.startMonitoring();
        await clipboardService.stopMonitoring();
        
        expect(clipboardService.enableClipboardMonitoring, isFalse);
        expect(clipboardService.isMonitoring, isFalse);
      });
    });

    group('Clipboard Content Processing', () {
      test('should detect clipboard content changes', () async {
        await clipboardService.enableMonitoring();
        
        bool streamReceived = false;
        String? receivedContent;
        
        clipboardService.clipboardStream.listen((content) {
          streamReceived = true;
          receivedContent = content;
        });
        
        const testContent = '这是一个测试内容';
        clipboardService.simulateClipboardContent(testContent);
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(streamReceived, isTrue);
        expect(receivedContent, equals(testContent));
        expect(clipboardService.currentClipboardContent, equals(testContent));
        expect(clipboardService.lastProcessedContent, equals(testContent));
      });

      test('should not process duplicate content', () async {
        await clipboardService.enableMonitoring();
        
        int streamCallCount = 0;
        clipboardService.clipboardStream.listen((_) {
          streamCallCount++;
        });
        
        const testContent = '重复内容测试';
        
        // Simulate same content twice
        clipboardService.simulateClipboardContent(testContent);
        clipboardService.simulateClipboardContent(testContent);
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(streamCallCount, equals(1)); // Should only receive once
      });

      test('should not process when monitoring is disabled', () async {
        // Ensure monitoring is disabled
        await clipboardService.disableMonitoring();
        
        bool streamReceived = false;
        clipboardService.clipboardStream.listen((_) {
          streamReceived = true;
        });
        
        clipboardService.simulateClipboardContent('测试内容');
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(streamReceived, isFalse);
      });

      test('should get current clipboard content', () async {
        const testContent = '当前剪贴板内容';
        clipboardService.simulateClipboardContent(testContent);
        
        final content = await clipboardService.getCurrentClipboardContent();
        expect(content, equals(testContent));
      });
    });

    group('Content Processing Logic', () {
      test('should process simple text content', () async {
        const simpleText = '这是一段简单的文本';
        final result = await clipboardService.processClipboardContent(simpleText);
        
        expect(result['content'], equals(simpleText));
        expect(result['source'], isNull);
        expect(result['author'], isNull);
        expect(result['work'], isNull);
      });

      test('should extract author from quote format', () async {
        const quoteWithAuthor = '生活不止眼前的苟且，还有诗和远方。——许巍';
        final result = await clipboardService.processClipboardContent(quoteWithAuthor);
        
        expect(result['content'], equals('生活不止眼前的苟且，还有诗和远方。'));
        expect(result['author'], equals('许巍'));
      });

      test('should extract work from book format', () async {
        const textWithBook = '在最深的绝望里，遇见最美丽的惊喜。《偷影子的人》';
        final result = await clipboardService.processClipboardContent(textWithBook);
        
        expect(result['content'], contains('在最深的绝望里'));
        expect(result['work'], equals('偷影子的人'));
      });

      test('should extract source from citation format', () async {
        const textWithSource = '知识就是力量。摘自《培根论文集》';
        final result = await clipboardService.processClipboardContent(textWithSource);
        
        expect(result['content'], contains('知识就是力量'));
        expect(result['source'], equals('培根论文集'));
      });

      test('should handle empty content', () async {
        final result = await clipboardService.processClipboardContent('');
        
        expect(result['content'], isEmpty);
        expect(result['source'], isNull);
        expect(result['author'], isNull);
        expect(result['work'], isNull);
      });

      test('should handle whitespace-only content', () async {
        final result = await clipboardService.processClipboardContent('   \n\t  ');
        
        expect(result['content'], isEmpty);
        expect(result['source'], isNull);
      });

      test('should handle complex quote formats', () async {
        const complexQuote = '"人生如梦，一尊还酹江月。"——苏轼《念奴娇·赤壁怀古》';
        final result = await clipboardService.processClipboardContent(complexQuote);
        
        expect(result['content'], contains('人生如梦'));
        expect(result['author'], contains('苏轼'));
        expect(result['work'], contains('念奴娇'));
      });
    });

    group('Quote Detection', () {
      test('should detect quote-like content', () {
        const quoteFormats = [
          '智慧源于生活。——佚名',
          '《论语》中说：学而时习之',
          '摘自《红楼梦》：满纸荒唐言',
          '选自鲁迅作品：希望是本无所谓有',
          '这是一段较长的具有哲理性的文本内容，应该被识别为类似引语的内容',
        ];
        
        for (final content in quoteFormats) {
          expect(clipboardService.isQuoteLikeContent(content), isTrue,
              reason: 'Should detect "$content" as quote-like');
        }
      });

      test('should not detect non-quote content', () {
        const nonQuoteFormats = [
          '',
          '短文本',
          '购物清单：牛奶、面包、鸡蛋',
          'https://example.com/some-url',
          '123456789',
        ];
        
        for (final content in nonQuoteFormats) {
          expect(clipboardService.isQuoteLikeContent(content), isFalse,
              reason: 'Should not detect "$content" as quote-like');
        }
      });

      test('should extract quote information', () {
        const testContent = '知识改变命运。——培根《论读书》';
        final info = clipboardService.extractQuoteInfo(testContent);
        
        expect(info['content'], contains('知识改变命运'));
        expect(info['author'], contains('培根'));
        expect(info['work'], contains('论读书'));
      });
    });

    group('Content Type Detection', () {
      test('should detect empty content', () {
        expect(clipboardService.getContentType(''), equals('empty'));
      });

      test('should detect short content', () {
        expect(clipboardService.getContentType('短'), equals('short'));
      });

      test('should detect long content', () {
        final longContent = 'x' * 600;
        expect(clipboardService.getContentType(longContent), equals('long'));
      });

      test('should detect quote content', () {
        const quoteContent = '人生若只如初见。——纳兰性德';
        expect(clipboardService.getContentType(quoteContent), equals('quote'));
      });

      test('should detect regular text content', () {
        const textContent = '这是一段普通的文本内容';
        expect(clipboardService.getContentType(textContent), equals('text'));
      });
    });

    group('Error Handling', () {
      test('should handle simulated errors', () {
        clipboardService.simulateError('剪贴板访问失败');
        
        expect(clipboardService.lastError, equals('剪贴板访问失败'));
      });

      test('should clear errors', () {
        clipboardService.simulateError('测试错误');
        expect(clipboardService.lastError, isNotNull);
        
        clipboardService.clearError();
        expect(clipboardService.lastError, isNull);
      });

      test('should handle processing errors gracefully', () async {
        // Process malformed content
        const malformedContent = 'Some——invalid——format——here';
        final result = await clipboardService.processClipboardContent(malformedContent);
        
        expect(result, isNotNull);
        expect(result['content'], isNotNull);
      });
    });

    group('History Management', () {
      test('should track last processed content', () async {
        await clipboardService.enableMonitoring();
        
        const content1 = '第一段内容';
        const content2 = '第二段内容';
        
        clipboardService.simulateClipboardContent(content1);
        expect(clipboardService.lastProcessedContent, equals(content1));
        
        clipboardService.simulateClipboardContent(content2);
        expect(clipboardService.lastProcessedContent, equals(content2));
      });

      test('should clear clipboard history', () async {
        await clipboardService.enableMonitoring();
        clipboardService.simulateClipboardContent('测试内容');
        
        expect(clipboardService.lastProcessedContent, isNotEmpty);
        expect(clipboardService.currentClipboardContent, isNotNull);
        
        clipboardService.clearHistory();
        
        expect(clipboardService.lastProcessedContent, isEmpty);
        expect(clipboardService.currentClipboardContent, isNull);
      });
    });

    group('Statistics and Monitoring', () {
      test('should provide processing statistics', () {
        final stats = clipboardService.getProcessingStats();
        
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats, containsPair('monitoring_enabled', anything));
        expect(stats, containsPair('is_monitoring', anything));
        expect(stats, containsPair('last_processed_length', anything));
        expect(stats, containsPair('has_current_content', anything));
        expect(stats, containsPair('initialized', anything));
      });

      test('should update statistics correctly', () async {
        await clipboardService.enableMonitoring();
        clipboardService.simulateClipboardContent('测试统计内容');
        
        final stats = clipboardService.getProcessingStats();
        
        expect(stats['monitoring_enabled'], isTrue);
        expect(stats['is_monitoring'], isTrue);
        expect(stats['last_processed_length'], greaterThan(0));
        expect(stats['has_current_content'], isTrue);
        expect(stats['initialized'], isTrue);
      });
    });

    group('Test Processing', () {
      test('should run test processing scenarios', () {
        // This tests the built-in test content processing
        clipboardService.testProcessing();
        
        // After test processing, should have some content
        expect(clipboardService.currentClipboardContent, isNotNull);
      });
    });

    group('State Management', () {
      test('should notify listeners on monitoring change', () async {
        bool notified = false;
        clipboardService.addListener(() {
          notified = true;
        });

        await clipboardService.enableMonitoring();
        expect(notified, isTrue);
      });

      test('should notify listeners on content change', () async {
        await clipboardService.enableMonitoring();
        
        bool notified = false;
        clipboardService.addListener(() {
          notified = true;
        });

        clipboardService.simulateClipboardContent('新内容');
        expect(notified, isTrue);
      });

      test('should notify listeners on error', () {
        bool notified = false;
        clipboardService.addListener(() {
          notified = true;
        });

        clipboardService.simulateError('测试错误');
        expect(notified, isTrue);
      });

      test('should notify listeners on history clear', () {
        bool notified = false;
        clipboardService.addListener(() {
          notified = true;
        });

        clipboardService.clearHistory();
        expect(notified, isTrue);
      });
    });

    group('Performance', () {
      test('should handle rapid content changes efficiently', () async {
        await clipboardService.enableMonitoring();
        
        final stopwatch = Stopwatch()..start();
        
        int receivedCount = 0;
        clipboardService.clipboardStream.listen((_) {
          receivedCount++;
        });
        
        // Simulate rapid changes
        for (int i = 0; i < 50; i++) {
          clipboardService.simulateClipboardContent('快速变化内容 $i');
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(receivedCount, equals(50));
      });

      test('should process large content efficiently', () async {
        final largeContent = 'x' * 10000; // 10KB content
        
        final stopwatch = Stopwatch()..start();
        final result = await clipboardService.processClipboardContent(largeContent);
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
        expect(result['content'], equals(largeContent));
      });

      test('should handle many concurrent processing requests', () async {
        final futures = <Future<Map<String, String?>>>[];
        
        for (int i = 0; i < 20; i++) {
          futures.add(clipboardService.processClipboardContent('并发处理内容 $i'));
        }
        
        final stopwatch = Stopwatch()..start();
        final results = await Future.wait(futures);
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(results.length, equals(20));
        expect(results.every((result) => result['content'] != null), isTrue);
      });
    });

    group('Edge Cases', () {
      test('should handle special characters in content', () async {
        const specialContent = '特殊字符测试：😀🎉"引号"《书名》——作者';
        final result = await clipboardService.processClipboardContent(specialContent);
        
        expect(result['content'], isNotNull);
        expect(result['content'], contains('特殊字符'));
      });

      test('should handle very long author names', () async {
        const longAuthorContent = '内容——这是一个非常非常非常非常非常长的作者名字超过正常长度';
        final result = await clipboardService.processClipboardContent(longAuthorContent);
        
        expect(result, isNotNull);
        expect(result['content'], equals('内容'));
      });

      test('should handle multiple format indicators', () async {
        const multiFormatContent = '复杂内容《书名》——作者摘自某处';
        final result = await clipboardService.processClipboardContent(multiFormatContent);
        
        expect(result, isNotNull);
        expect(result['content'], isNotNull);
      });

      test('should handle malformed quote patterns', () async {
        const malformedContent = '内容——————多个分隔符《》空书名';
        final result = await clipboardService.processClipboardContent(malformedContent);
        
        expect(result, isNotNull);
        expect(result['content'], isNotNull);
      });

      test('should handle concurrent monitoring operations', () async {
        // Start monitoring multiple times concurrently
        final futures = <Future<void>>[];
        for (int i = 0; i < 5; i++) {
          futures.add(clipboardService.startMonitoring());
        }
        
        await Future.wait(futures);
        expect(clipboardService.isMonitoring, isTrue);
        
        // Stop monitoring multiple times concurrently
        final stopFutures = <Future<void>>[];
        for (int i = 0; i < 5; i++) {
          stopFutures.add(clipboardService.stopMonitoring());
        }
        
        await Future.wait(stopFutures);
        expect(clipboardService.isMonitoring, isFalse);
      });
    });
  });
}