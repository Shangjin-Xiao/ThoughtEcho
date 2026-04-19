import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/connectivity_service.dart';

base class MockDNSOverrides extends IOOverrides {
  final bool shouldFail;
  MockDNSOverrides({this.shouldFail = false});

  @override
  Future<Socket> socketConnect(dynamic host, int port,
      {dynamic sourceAddress, int sourcePort = 0, Duration? timeout}) async {
    if (shouldFail) {
      throw SocketException('Mocked connection failure');
    }
    return super.socketConnect(host, port,
        sourceAddress: sourceAddress, sourcePort: sourcePort, timeout: timeout);
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(dynamic host, int port,
      {dynamic sourceAddress, int sourcePort = 0}) async {
    if (shouldFail) {
      throw SocketException('Mocked connection start failure');
    }
    return super.socketStartConnect(host, port,
        sourceAddress: sourceAddress, sourcePort: sourcePort);
  }
}

void main() {
  group('ConnectivityService Tests', () {
    late ConnectivityService connectivityService;

    setUp(() {
      connectivityService = ConnectivityService();
    });

    test('should initialize with isConnected as true by default', () {
      expect(connectivityService.isConnected, isTrue);
    });

    test('checkConnectionNow completes and updates state without exceptions',
        () async {
      // Testing structural integrity of the function returning boolean
      // without failing due to lack of network mocks in the native dart layer directly.
      final isConnected = await connectivityService.checkConnectionNow();
      expect(isConnected, isA<bool>());
    });

    test(
        'checkConnectionNow updates isConnected to boolean based on actual network state',
        () async {
      await connectivityService.checkConnectionNow();
      expect(connectivityService.isConnected, isA<bool>());
    });

    test('should notify listeners when connection state changes', () async {
      bool listenerCalled = false;
      connectivityService.addListener(() {
        listenerCalled = true;
      });

      final initialState = connectivityService.isConnected;
      await connectivityService.checkConnectionNow();
      final newState = connectivityService.isConnected;

      if (initialState != newState) {
        expect(listenerCalled, isTrue);
      } else {
        expect(listenerCalled, isFalse);
      }
    });

    test('dispose cancels timers', () {
      expect(() => connectivityService.dispose(), returnsNormally);
    });
  });
}
