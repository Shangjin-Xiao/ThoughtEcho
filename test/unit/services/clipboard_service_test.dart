/// Basic unit tests for ClipboardService
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:thoughtecho/services/clipboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardService Tests', () {
    late ClipboardService clipboardService;
    String? clipboardText;

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall methodCall,
      ) async {
        if (methodCall.method == 'Clipboard.setData') {
          clipboardText = methodCall.arguments['text'] as String?;
          return null;
        }
        if (methodCall.method == 'Clipboard.getData') {
          if (clipboardText == null) return null;
          return <String, dynamic>{'text': clipboardText};
        }
        return null;
      });
    });

    setUp(() {
      clipboardText = null;
      clipboardService = ClipboardService();
    });

    test('should create ClipboardService instance', () {
      expect(clipboardService, isNotNull);
    });

    test('should have basic functionality', () {
      expect(() => clipboardService.toString(), returnsNormally);
    });

    test('skips clipboard check once after note notification navigation',
        () async {
      clipboardService.setEnableClipboardMonitoring(true);

      ClipboardService.suppressNextCheckForNotificationNavigation();

      expect(await clipboardService.checkClipboard(), isNull);
      expect(clipboardService.shouldSkipNextClipboardCheck, isFalse);
    });

    test('extracts source before trailing author without dropping clipboard',
        () async {
      clipboardService.setEnableClipboardMonitoring(true);
      await Clipboard.setData(
        const ClipboardData(text: 'Quote body 《Source Book》 — Author'),
      );

      final result = await clipboardService.checkClipboard();

      expect(result, isNotNull);
      expect(result!['content'], 'Quote body');
      expect(result['author'], 'Author');
      expect(result['source'], 'Source Book');
    });

    test('extracts author before trailing source without dropping clipboard',
        () async {
      clipboardService.setEnableClipboardMonitoring(true);
      await Clipboard.setData(
        const ClipboardData(text: 'Quote body — Author 《Source Book》'),
      );

      final result = await clipboardService.checkClipboard();

      expect(result, isNotNull);
      expect(result!['content'], 'Quote body');
      expect(result['author'], 'Author');
      expect(result['source'], 'Source Book');
    });

    test('keeps the signature line author when it stands on its own line',
        () async {
      clipboardService.setEnableClipboardMonitoring(true);
      await Clipboard.setData(
        const ClipboardData(text: '人生若只如初见\n——纳兰性德'),
      );

      final result = await clipboardService.checkClipboard();

      expect(result!['content'], '人生若只如初见');
      expect(result['author'], '纳兰性德');
    });

    test('cuts the trailing source only, keeping an identical earlier one',
        () async {
      clipboardService.setEnableClipboardMonitoring(true);
      await Clipboard.setData(
        const ClipboardData(text: '《活着》里最重的一句话出自《活着》'),
      );

      final result = await clipboardService.checkClipboard();

      // 旧实现用 replaceFirst 删掉的是靠前那个同名书名号，正文会被改坏
      expect(result!['content'], '《活着》里最重的一句话出自');
      expect(result['source'], '活着');
    });

    test('does not treat a markdown list item as an author', () async {
      clipboardService.setEnableClipboardMonitoring(true);
      const text = '购物清单：\n- 苹果\n  - 香蕉';
      await Clipboard.setData(const ClipboardData(text: text));

      final result = await clipboardService.checkClipboard();

      expect(result!['content'], text);
      expect(result['author'], isNull);
      expect(result['source'], isNull);
    });

    test('does not treat a trailing date as an author', () async {
      clipboardService.setEnableClipboardMonitoring(true);
      const text = '周会纪要 2026-08-15';
      await Clipboard.setData(const ClipboardData(text: text));

      final result = await clipboardService.checkClipboard();

      expect(result!['content'], text);
      expect(result['author'], isNull);
    });

    test('does not treat a trailing url tail as an author', () async {
      clipboardService.setEnableClipboardMonitoring(true);
      const text = '参考 https://example.com/post/a-bcde';
      await Clipboard.setData(const ClipboardData(text: text));

      final result = await clipboardService.checkClipboard();

      expect(result!['content'], text);
      expect(result['author'], isNull);
    });

    test('does not treat a trailing parenthetical as a source', () async {
      clipboardService.setEnableClipboardMonitoring(true);
      const text = '今天心情不错（真的很好）';
      await Clipboard.setData(const ClipboardData(text: text));

      final result = await clipboardService.checkClipboard();

      expect(result!['content'], text);
      expect(result['source'], isNull);
    });

    test('keeps the text intact when it is nothing but a signature', () async {
      clipboardService.setEnableClipboardMonitoring(true);
      const text = '《人间失格》';
      await Clipboard.setData(const ClipboardData(text: text));

      final result = await clipboardService.checkClipboard();

      expect(result!['content'], text);
      expect(result['source'], isNull);
    });
  });
}
