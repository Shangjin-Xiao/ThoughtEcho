import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/home/home_refresh_coordinator.dart';
import 'package:thoughtecho/services/connectivity_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

class _Connectivity extends ChangeNotifier implements ConnectivityService {
  _Connectivity(this.events);

  final List<String> events;

  @override
  bool get isConnected => true;

  @override
  Future<bool> checkConnectionNow() async {
    events.add('connectivity');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Location extends ChangeNotifier implements LocationService {
  _Location(this.events);

  final List<String> events;

  @override
  bool get hasLocationPermission => false;

  @override
  bool get isLocationServiceEnabled => false;

  @override
  Future<void> refreshServiceStatus() async {
    events.add('location');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Weather extends ChangeNotifier implements WeatherService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('refresh updates environment before refreshing page content', (
    tester,
  ) async {
    final events = <String>[];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectivityService>.value(
            value: _Connectivity(events),
          ),
          ChangeNotifierProvider<LocationService>.value(
            value: _Location(events),
          ),
          ChangeNotifierProvider<WeatherService>.value(value: _Weather()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final coordinator = HomeRefreshCoordinator(
                  context: context,
                  isMounted: () => true,
                  refreshQuote: () async => events.add('quote'),
                  refreshPrompt: ({bool initialLoad = false}) async {
                    events.add(initialLoad ? 'prompt-initial' : 'prompt');
                  },
                );
                return ElevatedButton(
                  onPressed: () => unawaited(coordinator.refresh()),
                  child: const Text('refresh'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('refresh'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(events.take(2), ['connectivity', 'location']);
    expect(events.sublist(2), containsAll(<String>['quote', 'prompt']));
  });
}
