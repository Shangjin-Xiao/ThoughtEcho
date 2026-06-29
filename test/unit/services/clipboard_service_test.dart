/// Basic unit tests for ClipboardService
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/clipboard_service.dart';

void main() {
  group('ClipboardService Tests', () {
    late ClipboardService clipboardService;

    setUp(() {
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
  });
}
