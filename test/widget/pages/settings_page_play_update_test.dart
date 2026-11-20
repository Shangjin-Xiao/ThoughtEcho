import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/core/config/distribution_config.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/pages/settings_page.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/update_dialog.dart';

import '../../test_harness.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  final AppSettings _appSettings = AppSettings();

  @override
  AppSettings get appSettings => _appSettings;

  @override
  LocalAISettings get localAISettings => const LocalAISettings();

  @override
  String? get localeCode => 'zh';

  @override
  int get trashRetentionDays => 30;

  @override
  int get anniversarySimulatedYear => 0;

  @override
  List<int> get anniversaryShownYears => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLogService extends ChangeNotifier implements UnifiedLogService {
  @override
  bool get isPersistenceEnabled => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWebDAVSyncService extends ChangeNotifier
    implements WebDAVSyncService {
  @override
  bool get enabled => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await TestHarness.initialize();
  });

  tearDown(() {
    DistributionConfig.resetDebugOverrides();
    UpdateBottomSheet.debugUrlLauncher = null;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Android Play 渠道点击设置页检查更新直接打开 Google Play，不发起 GitHub 更新检查',
    (tester) async {
      DistributionConfig.debugChannelOverride = DistributionChannel.play;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final launchedUris = <Uri>[];
      UpdateBottomSheet.debugUrlLauncher = (uri, {required mode}) async {
        launchedUris.add(uri);
        return true;
      };

      final settingsService = _TestSettingsService();
      final locationService = LocationService();
      final weatherService = WeatherService();
      final logService = _TestLogService();
      final webdavService = _TestWebDAVSyncService();
      addTearDown(settingsService.dispose);
      addTearDown(locationService.dispose);
      addTearDown(weatherService.dispose);
      addTearDown(logService.dispose);
      addTearDown(webdavService.dispose);

      final appTheme = AppTheme();
      await appTheme.setThemeStyle(ThemeStyle.defaultStyle);
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(
              value: settingsService,
            ),
            ChangeNotifierProvider<LocationService>.value(
              value: locationService,
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: weatherService,
            ),
            ChangeNotifierProvider<UnifiedLogService>.value(
              value: logService,
            ),
            ChangeNotifierProvider<WebDAVSyncService>.value(
              value: webdavService,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: appTheme.createLightThemeData().copyWith(
                  platform: TargetPlatform.android,
                ),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkUpdateFinder = find.text(l10n.settingsCheckUpdate);
      await tester.scrollUntilVisible(
        checkUpdateFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(checkUpdateFinder);
      await tester.pumpAndSettle();

      expect(
        launchedUris.map((u) => u.toString()).toList(),
        equals(['market://details?id=com.shangjin.thoughtecho']),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
