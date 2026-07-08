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
  });
}
