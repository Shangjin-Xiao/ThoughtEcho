import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/core/config/distribution_config.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';
import 'package:thoughtecho/pages/smart_push_settings_page.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../test_harness.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  final AppSettings _appSettings = AppSettings();

  @override
  AppSettings get appSettings => _appSettings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  @override
  T? resolvePlatformSpecificImplementation<
          T extends FlutterLocalNotificationsPlatform>() =>
      null;

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancel(int id, {String? tag}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDatabaseService extends ChangeNotifier implements DatabaseService {
  @override
  Future<List<NoteTag>> getTags() async => const [];

  @override
  Future<List<Quote>> getAllQuotes({
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async =>
      const [];

  @override
  Future<List<Quote>> getQuotesForSmartPush({
    int limit = 200,
    String orderBy = 'q.date DESC',
    bool includeDeleted = false,
  }) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> getLocalDailyQuote({
    String offlineQuoteSource = 'tagOnly',
  }) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryPreferences implements AppPreferencesService {
  final Map<String, Object> values = {};

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.timeZoneDatabase.add(
      tz.Location(
        'Etc/GMT-8',
        [tz.minTime],
        [0],
        const [
          tz.TimeZone(
            8 * Duration.millisecondsPerHour,
            isDst: false,
            abbreviation: '+08',
          ),
        ],
      ),
    );
    tz.setLocalLocation(tz.getLocation('Etc/GMT-8'));
  });

  setUp(() async {
    await TestHarness.initialize();
  });

  tearDown(() {
    DistributionConfig.resetDebugOverrides();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> pumpSettingsPage(
    WidgetTester tester, {
    required DistributionChannel channel,
    required PushPermissionStatus permissionStatus,
    required VoidCallback onOpenSystemSettings,
  }) async {
    DistributionConfig.debugChannelOverride = channel;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final storage = _MemoryPreferences();
    storage.values['smart_push_settings_v2'] = jsonEncode(
      SmartPushSettings.defaultSettings().copyWith(enabled: true).toJson(),
    );
    final db = _FakeDatabaseService();
    final smartPushService = SmartPushService(
      databaseService: db,
      locationService: LocationService(),
      mmkvService: storage,
      notificationsPlugin: _NoopNotificationsPlugin(),
      isAndroidOverride: true,
      isIOSOverride: false,
      canScheduleExactAlarmsOverride: () async =>
          permissionStatus.exactAlarmEnabled,
      permissionStatusOverride: () async => permissionStatus,
      openSystemAppSettingsOverride: () async => onOpenSystemSettings(),
    );
    final settingsService = _TestSettingsService();
    addTearDown(settingsService.dispose);
    addTearDown(smartPushService.dispose);
    addTearDown(db.dispose);
    await smartPushService.loadSettingsForBackground();

    final appTheme = AppTheme();
    await appTheme.setThemeStyle(ThemeStyle.defaultStyle);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider<DatabaseService>.value(value: db),
          ChangeNotifierProvider<SmartPushService>.value(
            value: smartPushService,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme.createLightThemeData().copyWith(
                platform: TargetPlatform.android,
              ),
          home: const SmartPushSettingsPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Play 渠道在权限已齐全时隐藏电池优化豁免按钮，展示后台电池设置引导并可跳转系统应用信息',
    (tester) async {
      var openSettingsCount = 0;
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      await pumpSettingsPage(
        tester,
        channel: DistributionChannel.play,
        permissionStatus: const PushPermissionStatus(
          notificationEnabled: true,
          exactAlarmEnabled: true,
          batteryOptimizationExempted: true,
          manufacturer: 'google',
          sdkVersion: 34,
          needsAutoStartPermission: false,
          autoStartGranted: true,
        ),
        onOpenSystemSettings: () => openSettingsCount++,
      );

      expect(find.text(l10n.smartPushBatteryOptimization), findsNothing);
      final guideFinder = find.byKey(
        const ValueKey('smart_push_play_battery_guide_tile'),
      );
      expect(guideFinder, findsOneWidget);
      expect(
        find.text(l10n.smartPushBackgroundBatteryGuideTitle),
        findsOneWidget,
      );

      await tester.ensureVisible(guideFinder);
      await tester.tap(guideFinder);
      await tester.pumpAndSettle();

      expect(openSettingsCount, equals(1));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    '标准渠道在未豁免电池优化时显示电池优化豁免入口，不显示 Play 专属后台电池说明项',
    (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      await pumpSettingsPage(
        tester,
        channel: DistributionChannel.standard,
        permissionStatus: const PushPermissionStatus(
          notificationEnabled: true,
          exactAlarmEnabled: true,
          batteryOptimizationExempted: false,
          manufacturer: 'google',
          sdkVersion: 34,
          needsAutoStartPermission: false,
          autoStartGranted: true,
        ),
        onOpenSystemSettings: () {},
      );

      expect(find.text(l10n.smartPushBatteryOptimization), findsOneWidget);
      expect(
        find.byKey(const ValueKey('smart_push_play_battery_guide_tile')),
        findsNothing,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
