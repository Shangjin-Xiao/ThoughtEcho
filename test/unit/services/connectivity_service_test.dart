import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/connectivity_service.dart';

class _EmptyRawInternetAddress implements InternetAddress {
  @override
  Uint8List get rawAddress => Uint8List(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  List<String>? mockConnectivityResults;
  bool shouldThrowPlatformException = false;

  setUp(() {
    ConnectivityService.isConnectedOverrideForTesting = null;
    ConnectivityService.dnsLookupForTesting = null;
    ConnectivityService.probeTimeoutOverrideForTesting = null;
    ConnectivityService.isWindowsOverrideForTesting = false;
    ConnectivityService.localInterfaceAddressesForTesting = null;
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
    ConnectivityService.dnsLookupForTesting = null;
    ConnectivityService.probeTimeoutOverrideForTesting = null;
    ConnectivityService.isWindowsOverrideForTesting = null;
    ConnectivityService.localInterfaceAddressesForTesting = null;
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

    test(
      'short-circuits immediately to false with 0 DNS lookups when local connectivity is none',
      () async {
        final service = ConnectivityService();
        ConnectivityService.isConnectedOverrideForTesting = true;
        await service.checkConnectionNow();
        ConnectivityService.isConnectedOverrideForTesting = null;

        mockConnectivityResults = ['none'];
        var dnsLookupCalls = 0;
        ConnectivityService.dnsLookupForTesting = (host) async {
          dnsLookupCalls += 1;
          return [InternetAddress.loopbackIPv4];
        };

        final stopwatch = Stopwatch()..start();
        final result = await service.checkConnectionNow();
        stopwatch.stop();

        expect(result, isFalse);
        expect(service.isConnected, isFalse);
        expect(dnsLookupCalls, 0);
        expect(stopwatch.elapsedMilliseconds, lessThan(200));

        // Empty list from platform channel should not falsely short-circuit; it falls back to DNS.
        mockConnectivityResults = <String>[];
        final emptyChannelResult = await service.checkConnectionNow();
        expect(emptyChannelResult, isTrue);
        expect(dnsLookupCalls, greaterThan(0));
      },
    );

    test(
      'on Windows falls back to DNS when plugin reports none with active adapter, and short-circuits when no active adapter exists',
      () async {
        final service = ConnectivityService();
        ConnectivityService.isWindowsOverrideForTesting = true;
        mockConnectivityResults = ['none'];

        var dnsLookupCalls = 0;
        ConnectivityService.dnsLookupForTesting = (host) async {
          dnsLookupCalls += 1;
          return [InternetAddress.loopbackIPv4];
        };

        // Active routable/LAN adapter present while Windows NCSI reported none: must probe DNS.
        ConnectivityService.localInterfaceAddressesForTesting = () async => [
              InternetAddress('192.0.2.1'),
            ];
        expect(await service.checkConnectionNow(), isTrue);
        expect(service.isConnected, isTrue);
        expect(dnsLookupCalls, greaterThan(0));

        // Only loopback / link-local (APIPA) or no adapters: must short-circuit with 0 DNS lookups.
        dnsLookupCalls = 0;
        ConnectivityService.localInterfaceAddressesForTesting = () async => [
              InternetAddress.loopbackIPv4,
              InternetAddress('169.254.10.20'),
            ];
        expect(await service.checkConnectionNow(), isFalse);
        expect(service.isConnected, isFalse);
        expect(dnsLookupCalls, 0);
      },
    );

    test(
      'falls back to DNS probe when checkConnectivity throws PlatformException or MissingPluginException',
      () async {
        final service = ConnectivityService();
        final queriedHosts = <String>[];
        ConnectivityService.dnsLookupForTesting = (host) async {
          queriedHosts.add(host);
          return [InternetAddress.loopbackIPv4];
        };

        // Case 1: PlatformException
        shouldThrowPlatformException = true;
        expect(await service.checkConnectionNow(), isTrue);
        expect(service.isConnected, isTrue);
        expect(queriedHosts, isNotEmpty);

        // Case 2: MissingPluginException (unregistered channel handler)
        queriedHosts.clear();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(connectivityChannel, null);
        expect(await service.checkConnectionNow(), isTrue);
        expect(service.isConnected, isTrue);
        expect(queriedHosts, isNotEmpty);
      },
    );

    test(
      'concurrent DNS race returns true near fast host latency even when first two hosts time out',
      () async {
        final service = ConnectivityService();
        final uncaughtErrors = <Object>[];
        final slowHostCompleters = <String, Completer<List<InternetAddress>>>{};

        ConnectivityService.dnsLookupForTesting = (host) {
          if (host == 'dns.google' || host == 'one.one.one.one') {
            final completer = Completer<List<InternetAddress>>();
            slowHostCompleters[host] = completer;
            return completer.future;
          }
          return Future<List<InternetAddress>>.delayed(
            const Duration(milliseconds: 30),
            () => [InternetAddress.loopbackIPv4],
          );
        };

        await runZonedGuarded(() async {
          final stopwatch = Stopwatch()..start();
          final isConnected = await service.checkConnectionNow();
          stopwatch.stop();

          expect(isConnected, isTrue);
          expect(service.isConnected, isTrue);
          // Should finish near the 30ms fast host rather than waiting 2 * 3000ms = 6000ms.
          expect(stopwatch.elapsedMilliseconds, lessThan(500));

          // Simulate slow losing branches failing later with TimeoutException / SocketException.
          slowHostCompleters['dns.google']!.completeError(
            TimeoutException(
              'Simulated 3s DNS timeout',
              const Duration(seconds: 3),
            ),
          );
          slowHostCompleters['one.one.one.one']!.completeError(
            const SocketException('Late lookup failure'),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }, (error, _) {
          uncaughtErrors.add(error);
        });

        expect(uncaughtErrors, isEmpty);
      },
    );

    test(
      'concurrent DNS race succeeds when first host throws SocketException immediately and another resolves later',
      () async {
        final service = ConnectivityService();
        ConnectivityService.dnsLookupForTesting = (host) async {
          if (host == 'dns.google') {
            throw const SocketException('Immediate DNS lookup failure');
          }
          if (host == 'one.one.one.one') {
            return <_EmptyRawInternetAddress>[_EmptyRawInternetAddress()];
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
          return [InternetAddress.loopbackIPv4];
        };

        final result = await service.checkConnectionNow();
        expect(result, isTrue);
        expect(service.isConnected, isTrue);
      },
    );

    test(
      'returns false within a single timeout window when all hosts time out or return empty addresses without uncaught errors',
      () async {
        final service = ConnectivityService();
        final uncaughtErrors = <Object>[];

        // Sub-case A: All 3 hosts return empty list / empty rawAddress immediately.
        ConnectivityService.dnsLookupForTesting = (host) async {
          if (host == 'dns.google') {
            return <InternetAddress>[];
          }
          return <InternetAddress>[_EmptyRawInternetAddress()];
        };
        expect(await service.checkConnectionNow(), isFalse);
        expect(service.isConnected, isFalse);

        // Sub-case B: All 3 hosts exceed timeout window and reject later.
        ConnectivityService.probeTimeoutOverrideForTesting =
            const Duration(milliseconds: 80);
        ConnectivityService.dnsLookupForTesting = (host) async {
          await Future<void>.delayed(const Duration(milliseconds: 180));
          throw SocketException('Delayed lookup error for $host');
        };

        late bool timedOutResult;
        final stopwatch = Stopwatch()..start();
        await runZonedGuarded(() async {
          timedOutResult = await service.checkConnectionNow();
          expect(timedOutResult, isFalse);
          expect(service.isConnected, isFalse);
          stopwatch.stop();
          // Single 80ms timeout window (well below 3 * 80ms = 240ms and before 180ms late errors).
          expect(stopwatch.elapsedMilliseconds, lessThan(175));

          // Let the 180ms late SocketExceptions fire to confirm none leak to Zone.
          await Future<void>.delayed(const Duration(milliseconds: 140));
        }, (error, _) {
          uncaughtErrors.add(error);
        });

        expect(uncaughtErrors, isEmpty);
      },
    );

    test(
      'deduplicates overlapping checkConnectionNow and init calls, notifies once on flip, and switches 15s/60s polling intervals',
      () {
        fakeAsync((async) {
          final service = ConnectivityService();

          // Start from known online state.
          ConnectivityService.isConnectedOverrideForTesting = true;
          service.checkConnectionNow();
          async.flushMicrotasks();
          expect(service.isConnected, isTrue);
          ConnectivityService.isConnectedOverrideForTesting = null;

          var notifyCount = 0;
          void listener() {
            notifyCount += 1;
          }

          service.addListener(listener);
          addTearDown(() => service.removeListener(listener));

          var dnsLookupCalls = 0;
          var shouldSucceedDns = false;
          ConnectivityService.dnsLookupForTesting = (host) async {
            dnsLookupCalls += 1;
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return shouldSucceedDns
                ? <InternetAddress>[InternetAddress.loopbackIPv4]
                : <InternetAddress>[];
          };

          final completedResults = <bool>[];
          var initCompleted = false;

          // Launch overlapping init() and 3 concurrent checkConnectionNow() calls.
          service.init().then((_) {
            initCompleted = true;
          });
          for (var i = 0; i < 3; i++) {
            service.checkConnectionNow().then(completedResults.add);
          }

          async.elapse(const Duration(milliseconds: 50));

          expect(initCompleted, isTrue);
          expect(completedResults, equals([false, false, false]));
          expect(service.isConnected, isFalse);
          // Only 1 probe round (3 hosts) instead of 4 * 3 = 12 DNS lookups.
          expect(dnsLookupCalls, 3);
          // State flipped true -> false once, so listeners notified exactly once.
          expect(notifyCount, 1);

          // Offline polling interval must be 15s: nothing at 14s, 1 probe round at 15s.
          dnsLookupCalls = 0;
          shouldSucceedDns = true;
          async.elapse(const Duration(seconds: 14));
          expect(dnsLookupCalls, 0);

          async.elapse(const Duration(seconds: 1, milliseconds: 50));
          expect(dnsLookupCalls, 3);
          expect(service.isConnected, isTrue);
          // State flipped false -> true once, notifying listeners a second time.
          expect(notifyCount, 2);

          // Online polling interval must switch to 60s: no probes at 15s or 59s, 1 probe round at 60s.
          dnsLookupCalls = 0;
          async.elapse(const Duration(seconds: 59));
          expect(dnsLookupCalls, 0);

          async.elapse(const Duration(seconds: 1, milliseconds: 50));
          expect(dnsLookupCalls, 3);
          // State remained true -> true, so no extra listener notification.
          expect(notifyCount, 2);
        });
      },
    );

    test('init and dispose manage connectivity state lifecycle', () async {
      final service = ConnectivityService();
      ConnectivityService.isConnectedOverrideForTesting = null;

      await service.init();
      service.addListener(() {});
      expect(service.hasListenersForTesting, isTrue);

      service.dispose();
      expect(service.hasListenersForTesting, isFalse);
    });
  });
}
