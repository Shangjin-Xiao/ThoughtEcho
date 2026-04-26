import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/pages/hitokoto_settings_page.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_setup.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  AppSettings _appSettings;
  final Future<void> Function(String provider)? onSetDailyQuoteProvider;
  final Future<void> Function(List<String> categories)?
      onSetApiNinjasCategories;

  _TestSettingsService({
    AppSettings? appSettings,
    this.onSetDailyQuoteProvider,
    this.onSetApiNinjasCategories,
  }) : _appSettings = appSettings ?? AppSettings();

  @override
  AppSettings get appSettings => _appSettings;

  @override
  String get dailyQuoteProvider => _appSettings.dailyQuoteProvider;

  @override
  Future<void> updateHitokotoType(String type) async {
    _appSettings = _appSettings.copyWith(hitokotoType: type);
    notifyListeners();
  }

  @override
  Future<void> setDailyQuoteProvider(String provider) async {
    if (onSetDailyQuoteProvider != null) {
      await onSetDailyQuoteProvider!(provider);
    }
    _appSettings = _appSettings.copyWith(dailyQuoteProvider: provider);
    notifyListeners();
  }

  @override
  List<String> get apiNinjasCategories => _appSettings.apiNinjasCategories;

  @override
  Future<void> setApiNinjasCategories(List<String> categories) async {
    if (onSetApiNinjasCategories != null) {
      await onSetApiNinjasCategories!(categories);
    }
    _appSettings = _appSettings.copyWith(apiNinjasCategories: categories);
    notifyListeners();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await TestSetup.setupWidgetTest();
  });

  Widget buildApp(
    SettingsService settings, {
    Future<bool> Function()? apiNinjasApiKeyStatusLoader,
  }) {
    return ChangeNotifierProvider<SettingsService>.value(
      value: settings,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HitokotoSettingsPage(
          apiNinjasApiKeyStatusLoader:
              apiNinjasApiKeyStatusLoader ?? (() async => false),
        ),
      ),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    SettingsService settings, {
    Future<bool> Function()? apiNinjasApiKeyStatusLoader,
  }) async {
    await tester.pumpWidget(
      buildApp(
        settings,
        apiNinjasApiKeyStatusLoader: apiNinjasApiKeyStatusLoader,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  testWidgets('一言设置页不显示离线一言数据源选项', (tester) async {
    final settings = _TestSettingsService();
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await pumpPage(tester, settings);

    expect(find.text(localizations.hitokotoSettings), findsOneWidget);
    expect(find.text(localizations.offlineQuoteSourceTitle), findsNothing);
    expect(find.text(localizations.offlineQuoteSourceTagOnly), findsNothing);
    expect(find.text(localizations.offlineQuoteSourceAll), findsNothing);
    expect(
      find.byType(ChoiceChip),
      findsNWidgets(ApiService.getDailyQuoteProviders(localizations).length),
    );
  });

  testWidgets('切换到其他 provider 时隐藏 Hitokoto 类型筛选', (tester) async {
    final settings = _TestSettingsService();
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await pumpPage(tester, settings);

    expect(find.text(localizations.typeSelection), findsOneWidget);

    await tester.tap(find.text(localizations.dailyQuoteApiZenQuotes));
    await tester.pumpAndSettle();

    expect(settings.dailyQuoteProvider, 'zenquotes');
    expect(find.text(localizations.typeSelection), findsNothing);
    expect(
      find.text(localizations.dailyQuoteProviderNoTypeSelection),
      findsOneWidget,
    );
  });

  testWidgets('选择 API Ninjas 时显示密钥和分类入口', (tester) async {
    final settings = _TestSettingsService();
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await pumpPage(tester, settings);

    await tester.tap(find.text(localizations.dailyQuoteApiApiNinjas));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text(localizations.dailyQuoteApiNinjasManageApiKey),
        findsOneWidget);
    expect(find.text(localizations.dailyQuoteApiNinjasCategorySelection),
        findsOneWidget);
    expect(
      find.text(localizations.dailyQuoteProviderNoTypeSelection),
      findsNothing,
    );
  });

  testWidgets('切换到 API Ninjas 时刷新密钥状态', (tester) async {
    final settings = _TestSettingsService();
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));
    var loadCount = 0;

    await pumpPage(
      tester,
      settings,
      apiNinjasApiKeyStatusLoader: () async {
        loadCount++;
        return true;
      },
    );
    expect(loadCount, 0);

    await tester.tap(find.text(localizations.dailyQuoteApiApiNinjas));
    await tester.pumpAndSettle();
    expect(loadCount, greaterThanOrEqualTo(1));

    expect(find.text(localizations.dailyQuoteApiNinjasApiKeyConfigured),
        findsOneWidget);
    expect(find.text(localizations.dailyQuoteApiNinjasApiKeyMissing),
        findsNothing);
  });

  testWidgets('API Ninjas 密钥状态加载失败时降级为未配置状态', (tester) async {
    final settings = _TestSettingsService();
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await pumpPage(
      tester,
      settings,
      apiNinjasApiKeyStatusLoader: () async =>
          throw Exception('key-status-failed'),
    );

    await tester.tap(find.text(localizations.dailyQuoteApiApiNinjas));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(localizations.dailyQuoteApiNinjasApiKeyMissing),
        findsOneWidget);
  });

  testWidgets('provider 保存完成前不显示保存成功提示', (tester) async {
    final saveCompleter = Completer<void>();
    final settings = _TestSettingsService(
      onSetDailyQuoteProvider: (_) => saveCompleter.future,
    );
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await pumpPage(tester, settings);

    await tester.tap(find.text(localizations.dailyQuoteApiZenQuotes));
    await tester.pump();

    expect(find.text(localizations.settingsSaved), findsNothing);

    saveCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text(localizations.settingsSaved), findsOneWidget);
  });

  testWidgets('provider 保存失败时显示错误提示', (tester) async {
    final settings = _TestSettingsService(
      onSetDailyQuoteProvider: (_) async => throw Exception('save-failed'),
    );
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await pumpPage(tester, settings);

    await tester.tap(find.text(localizations.dailyQuoteApiZenQuotes));
    await tester.pumpAndSettle();

    expect(
      find.text(localizations.saveFailed('Exception: save-failed')),
      findsOneWidget,
    );
  });

  testWidgets('provider 保存失败时不会提前刷新 API Ninjas 密钥状态', (tester) async {
    final settings = _TestSettingsService(
      onSetDailyQuoteProvider: (_) async => throw Exception('save-failed'),
    );
    var loadCount = 0;
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await pumpPage(
      tester,
      settings,
      apiNinjasApiKeyStatusLoader: () async {
        loadCount++;
        return true;
      },
    );

    await tester.tap(find.text(localizations.dailyQuoteApiApiNinjas));
    await tester.pumpAndSettle();

    expect(loadCount, 0);
    expect(settings.dailyQuoteProvider, 'hitokoto');
    expect(find.text(localizations.dailyQuoteApiNinjasApiKeyConfigured),
        findsNothing);
  });

  testWidgets('保存 API Ninjas 分类失败时显示错误提示', (tester) async {
    var saveAttemptCount = 0;
    final settings = _TestSettingsService(
      onSetApiNinjasCategories: (_) async {
        saveAttemptCount++;
        throw Exception('categories-failed');
      },
    );
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await pumpPage(tester, settings);

    await tester.tap(find.text(localizations.dailyQuoteApiApiNinjas));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(localizations.dailyQuoteApiNinjasCategorySelection),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester
        .tap(find.text(localizations.dailyQuoteApiNinjasCategorySelection));
    await tester.pumpAndSettle();

    expect(
      find.text(localizations.dailyQuoteApiNinjasCategorySearchHint),
      findsOneWidget,
    );

    final categoryPageContext = tester.element(
      find.text(localizations.dailyQuoteApiNinjasCategorySearchHint),
    );
    Navigator.of(categoryPageContext).pop(const <String>['wisdom']);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(saveAttemptCount, 1);
    expect(settings.apiNinjasCategories, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
