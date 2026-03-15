import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/global_exception_handler.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobalExceptionHandler', () {
    setUp(() async {
      await TestSetup.setupUnitTest();
      GlobalExceptionHandler.clearDeferredErrors();
    });

    test('reports platform channel global capture as unavailable', () {
      GlobalExceptionHandler.initialize();

      final stats = GlobalExceptionHandler.getExceptionStats();

      expect(stats['platformChannelGlobalCaptureSupported'], isFalse);
    });
  });
}
