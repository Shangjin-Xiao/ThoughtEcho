import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/services/connectivity_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/widgets/daily_quote_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'loads local daily quote without waiting for SmartPush startup',
    (tester) async {
      final databaseService = _LocalQuoteDatabaseService();
      final locationService = LocationService();
      final smartPushService = SmartPushService(
        databaseService: databaseService,
        locationService: locationService,
        mmkvService: MMKVService(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(
              value: _LocalOnlySettingsService(),
            ),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
            ChangeNotifierProvider<ConnectivityService>.value(
              value: _ConnectedConnectivityService(),
            ),
            ChangeNotifierProvider<SmartPushService>.value(
              value: smartPushService,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: DailyQuoteView(onAddQuote: (_, __, ___, ____) {}),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('本地启动一言'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _LocalQuoteDatabaseService extends DatabaseService {
  _LocalQuoteDatabaseService() : super.forTesting();

  @override
  Future<Map<String, dynamic>?> getLocalDailyQuote({
    String offlineQuoteSource = 'tagOnly',
  }) async {
    return {
      'content': '本地启动一言',
      'source': '',
      'author': '',
      'type': 'local',
      'from_who': '',
      'from': '',
      'provider': 'local',
    };
  }
}

class _LocalOnlySettingsService extends ChangeNotifier
    implements SettingsService {
  @override
  AppSettings get appSettings =>
      AppSettings.defaultSettings().copyWith(useLocalQuotesOnly: true);

  @override
  LocalAISettings get localAISettings => LocalAISettings.defaultSettings();

  @override
  String get dailyQuoteProvider => 'hitokoto';

  @override
  String get offlineQuoteSource => 'tagOnly';

  @override
  List<String> get apiNinjasCategories => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName}');
}

class _ConnectedConnectivityService extends ChangeNotifier
    implements ConnectivityService {
  @override
  bool get isConnected => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ConnectivityService.${invocation.memberName}');
}
