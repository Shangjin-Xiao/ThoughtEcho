import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/preferences_detail_page.dart';
import 'package:thoughtecho/services/clipboard_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  bool _excerptIntentEnabled;

  _TestSettingsService({bool excerptIntentEnabled = true})
      : _excerptIntentEnabled = excerptIntentEnabled;

  @override
  bool get excerptIntentEnabled => _excerptIntentEnabled;

  @override
  Future<void> setExcerptIntentEnabled(bool enabled) async {
    _excerptIntentEnabled = enabled;
    notifyListeners();
  }

  @override
  bool get showFavoriteButton => true;

  @override
  Future<void> setShowFavoriteButton(bool enabled) async {}

  @override
  bool get showExactTime => false;

  @override
  Future<void> setShowExactTime(bool enabled) async {}

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  Future<void> setPrioritizeBoldContentInCollapse(bool enabled) async {}

  @override
  bool get useLocalQuotesOnly => false;

  @override
  Future<void> setUseLocalQuotesOnly(bool enabled) async {}

  @override
  bool get autoAttachLocation => false;

  @override
  Future<void> setAutoAttachLocation(bool enabled) async {}

  @override
  bool get autoAttachWeather => false;

  @override
  Future<void> setAutoAttachWeather(bool enabled) async {}

  @override
  String? get defaultAuthor => null;

  @override
  Future<void> setDefaultAuthor(String? author) async {}

  @override
  String? get defaultSource => null;

  @override
  Future<void> setDefaultSource(String? source) async {}

  @override
  List<String> get defaultTagIds => const [];

  @override
  Future<void> setDefaultTagIds(List<String> tagIds) async {}

  @override
  bool get todayThoughtsUseAI => true;

  @override
  Future<void> setTodayThoughtsUseAI(bool enabled) async {}

  @override
  bool get reportInsightsUseAI => false;

  @override
  Future<void> setReportInsightsUseAI(bool enabled) async {}

  @override
  bool get aiCardGenerationEnabled => true;

  @override
  Future<void> setAICardGenerationEnabled(bool enabled) async {}

  @override
  bool get requireBiometricForHidden => false;

  @override
  Future<void> setRequireBiometricForHidden(bool enabled) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestClipboardService extends ChangeNotifier implements ClipboardService {
  bool _enableClipboardMonitoring = false;

  @override
  bool get enableClipboardMonitoring => _enableClipboardMonitoring;

  @override
  void setEnableClipboardMonitoring(bool value) {
    _enableClipboardMonitoring = value;
    notifyListeners();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (methodCall) async {
      switch (methodCall.method) {
        case 'isDeviceSupported':
        case 'deviceSupportsBiometrics':
        case 'canCheckBiometrics':
          return false;
        case 'getAvailableBiometrics':
          return <String>[];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, null);
  });

  Widget buildApp(SettingsService settings, ClipboardService clipboard) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<ClipboardService>.value(value: clipboard),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PreferencesDetailPage(),
      ),
    );
  }

  testWidgets('偏好设置页显示摘录开关并可切换', (tester) async {
    final settings = _TestSettingsService();
    final clipboard = _TestClipboardService();

    await tester.pumpWidget(buildApp(settings, clipboard));
    await tester.pumpAndSettle();

    final titleFinder = find.text('摘录到心迹');
    await tester.scrollUntilVisible(
      titleFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(titleFinder, findsOneWidget);
    expect(settings.excerptIntentEnabled, isTrue);

    await tester.tap(find.byType(Switch).at(7));
    await tester.pumpAndSettle();

    expect(settings.excerptIntentEnabled, isFalse);
  });
}
