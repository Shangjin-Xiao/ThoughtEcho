import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  List<String>? mockConnectivityResults;
  bool shouldThrowPlatformException = false;

  setUp(() {
    ConnectivityService.isConnectedOverrideForTesting = null;
    mockConnectivityResults = ['wifi'];
    shouldThrowPlatformException = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (
      MethodCall methodCall,
    ) async {
      if (shouldThrowPlatformException) {
        throw PlatformException(
          code: 'UNAVAILABLE',
          message: 'Connectivity service unavailable',
        );
      }
      if (methodCall.method == 'check') {
        return mockConnectivityResults;
      }
      return null;
    });
  });

  tearDown(() {
    ConnectivityService.isConnectedOverrideForTesting = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  group('ConnectivityService Tests', () {
    test('singleton instance check', () {
      final instance1 = ConnectivityService();
      final instance2 = ConnectivityService();
      expect(identical(instance1, instance2), isTrue);
    });

    test('isConnectedOverrideForTesting overrides isConnected', () {
      final service = ConnectivityService();

      ConnectivityService.isConnectedOverrideForTesting = true;
      expect(service.isConnected, isTrue);

      ConnectivityService.isConnectedOverrideForTesting = false;
      expect(service.isConnected, isFalse);

      ConnectivityService.isConnectedOverrideForTesting = null;
      // Default initial or updated state
      expect(service.isConnected, isA<bool>());
    });

    test('checkConnectionNow returns override value when set', () async {
      final service = ConnectivityService();

      ConnectivityService.isConnectedOverrideForTesting = true;
      expect(await service.checkConnectionNow(), isTrue);

      ConnectivityService.isConnectedOverrideForTesting = false;
      expect(await service.checkConnectionNow(), isFalse);
    });

    test('isCellularConnection detects mobile data correctly', () async {
      final service = ConnectivityService();

      // Cellular connection
      mockConnectivityResults = ['mobile'];
      expect(await service.isCellularConnection(), isTrue);

      // Wifi connection
      mockConnectivityResults = ['wifi'];
      expect(await service.isCellularConnection(), isFalse);

      // Multiple connections including mobile
      mockConnectivityResults = ['wifi', 'mobile'];
      expect(await service.isCellularConnection(), isTrue);

      // No connection
      mockConnectivityResults = ['none'];
      expect(await service.isCellularConnection(), isFalse);
    });

    test(
      'isCellularConnection handles exception safely and returns false',
      () async {
        final service = ConnectivityService();
        shouldThrowPlatformException = true;

        final isCellular = await service.isCellularConnection();
        expect(isCellular, isFalse);
      },
    );

    test(
      'checkConnectionNow performs check and updates connection state',
      () async {
        final service = ConnectivityService();
        ConnectivityService.isConnectedOverrideForTesting = null;

        final isConnected = await service.checkConnectionNow();
        expect(isConnected, isA<bool>());
        expect(service.isConnected, equals(isConnected));
      },
    );

    test('listeners are notified when connectivity state changes', () async {
      final service = ConnectivityService();
      ConnectivityService.isConnectedOverrideForTesting = true;
      await service.checkConnectionNow();
      expect(service.isConnected, isTrue);

      bool listenerCalled = false;
      void listener() {
        listenerCalled = true;
      }

      service.addListener(listener);

      // Force connection state transition to false
      ConnectivityService.isConnectedOverrideForTesting = false;
      await service.checkConnectionNow();

      service.removeListener(listener);
      ConnectivityService.isConnectedOverrideForTesting = null;

      expect(listenerCalled, isTrue);
      expect(service.isConnected, isFalse);
    });

    test('init and dispose manage connectivity state lifecycle', () async {
      final service = ConnectivityService();
      ConnectivityService.isConnectedOverrideForTesting = null;

      await service.init();
      service.addListener(() {});
      expect(service.hasListeners, isTrue);

      service.dispose();
      expect(service.hasListeners, isFalse);
    });
  });
}
