import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/pages/hitokoto_settings_page.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  AppSettings _appSettings;

  _TestSettingsService({
    AppSettings? appSettings,
  }) : _appSettings = appSettings ?? AppSettings();

  @override
  AppSettings get appSettings => _appSettings;

  @override
  Future<void> updateHitokotoType(String type) async {
    _appSettings = _appSettings.copyWith(hitokotoType: type);
    notifyListeners();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp(SettingsService settings) {
    return ChangeNotifierProvider<SettingsService>.value(
      value: settings,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HitokotoSettingsPage(),
      ),
    );
  }

  testWidgets('一言设置页不显示离线一言数据源选项', (tester) async {
    final settings = _TestSettingsService();
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.pumpWidget(buildApp(settings));
    await tester.pumpAndSettle();

    expect(find.text(localizations.hitokotoSettings), findsOneWidget);
    expect(find.text(localizations.offlineQuoteSourceTitle), findsNothing);
    expect(find.text(localizations.offlineQuoteSourceTagOnly), findsNothing);
    expect(find.text(localizations.offlineQuoteSourceAll), findsNothing);
  });
}
