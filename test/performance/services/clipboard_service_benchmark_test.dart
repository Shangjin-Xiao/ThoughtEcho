import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/clipboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maximum-length malformed clipboard attributions finish promptly',
      () async {
    final service = ClipboardService()..setEnableClipboardMonitoring(true);
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      service.dispose();
    });

    for (final repeated in ['—', '-', ' ', '《']) {
      // Exactly the largest accepted clipboard size; ':' prevents attribution.
      clipboardText = 'Body${repeated * 4995}:';
      final timer = Stopwatch()..start();
      final result = await service.checkClipboard();
      timer.stop();

      expect(result!['content'], clipboardText);
      expect(result['author'], isNull);
      expect(result['source'], isNull);
      // Generous allowance for cold regex compilation and shared CI hosts.
      // The vulnerable dash search blocks for several seconds at this size.
      expect(timer.elapsed, lessThan(const Duration(seconds: 1)),
          reason: 'Repeated "$repeated" must not stall clipboard checks');
    }
  });
}
