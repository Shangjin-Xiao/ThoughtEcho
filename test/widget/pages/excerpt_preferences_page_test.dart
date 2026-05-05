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
  bool _showNoteEditTime;
  bool _skipNonFullscreenEditor;
  bool _useLocalQuotesOnly;
  String _offlineQuoteSource;

  _TestSettingsService({
    bool excerptIntentEnabled = true,
    bool showNoteEditTime = false,
    bool skipNonFullscreenEditor = false,
    bool useLocalQuotesOnly = false,
    String offlineQuoteSource = 'tagOnly',
  })  : _excerptIntentEnabled = excerptIntentEnabled,
        _showNoteEditTime = showNoteEditTime,
        _skipNonFullscreenEditor = skipNonFullscreenEditor,
        _useLocalQuotesOnly = useLocalQuotesOnly,
        _offlineQuoteSource = offlineQuoteSource;

  @override
  bool get excerptIntentEnabled => _excerptIntentEnabled;

  @override
  Future<void> setExcerptIntentEnabled(bool enabled) async {
    _excerptIntentEnabled = enabled;
    notifyListeners();
  }

  @override
  bool get showNoteEditTime => _showNoteEditTime;

  @override
  Future<void> setShowNoteEditTime(bool enabled) async {
    _showNoteEditTime = enabled;
    notifyListeners();
  }

  @override
  bool get skipNonFullscreenEditor => _skipNonFullscreenEditor;

  @override
  Future<void> setSkipNonFullscreenEditor(bool enabled) async {
    _skipNonFullscreenEditor = enabled;
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
  bool get useLocalQuotesOnly => _useLocalQuotesOnly;

  @override
  Future<void> setUseLocalQuotesOnly(bool enabled) async {
    _useLocalQuotesOnly = enabled;
    notifyListeners();
  }

  @override
  String get offlineQuoteSource => _offlineQuoteSource;

  @override
  Future<void> setOfflineQuoteSource(String source) async {
    _offlineQuoteSource = source;
    notifyListeners();
  }

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

  Finder findSwitchForText(String text) {
    final textFinder = find.text(text);
    return find.descendant(
      of: find.ancestor(of: textFinder, matching: find.byType(ListTile)),
      matching: find.byType(Switch),
    );
  }

  testWidgets('偏好设置页显示摘录开关并可切换', (tester) async {
    final settings = _TestSettingsService();
    final clipboard = _TestClipboardService();

    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.pumpWidget(buildApp(settings, clipboard));
    await tester.pumpAndSettle();

    final titleFinder = find.text(localizations.excerptIntentEnabled);
    await tester.scrollUntilVisible(
      titleFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(titleFinder, findsOneWidget);
    expect(settings.excerptIntentEnabled, isTrue);

    await tester.tap(findSwitchForText(localizations.excerptIntentEnabled));
    await tester.pumpAndSettle();

    expect(settings.excerptIntentEnabled, isFalse);
  });

  testWidgets('偏好设置页显示编辑时间开关并可切换', (tester) async {
    final settings = _TestSettingsService();
    final clipboard = _TestClipboardService();

    await tester.pumpWidget(buildApp(settings, clipboard));
    await tester.pumpAndSettle();

    const titleText = '显示笔记编辑时间';
    final titleFinder = find.text(titleText);
    await tester.scrollUntilVisible(
      titleFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(titleFinder, findsOneWidget);
    expect(settings.showNoteEditTime, isFalse);

    await tester.tap(findSwitchForText(titleText));
    await tester.pumpAndSettle();

    expect(settings.showNoteEditTime, isTrue);
  });

  testWidgets('偏好设置页显示直接进入全屏编辑器开关并可切换', (tester) async {
    final settings = _TestSettingsService();
    final clipboard = _TestClipboardService();

    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.pumpWidget(buildApp(settings, clipboard));
    await tester.pumpAndSettle();

    final titleFinder = find.text(localizations.skipNonFullscreenEditor);
    await tester.scrollUntilVisible(
      titleFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(titleFinder, findsOneWidget);
    expect(settings.skipNonFullscreenEditor, isFalse);

    await tester.tap(titleFinder);
    await tester.pumpAndSettle();

    expect(settings.skipNonFullscreenEditor, isTrue);
  });

  testWidgets('偏好设置页始终显示离线一言数据源选项', (tester) async {
    final settings = _TestSettingsService(
      useLocalQuotesOnly: false,
      offlineQuoteSource: 'tagOnly',
    );
    final clipboard = _TestClipboardService();
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.pumpWidget(buildApp(settings, clipboard));
    await tester.pumpAndSettle();

    final titleFinder = find.text(localizations.offlineQuoteSourceTitle);
    await tester.scrollUntilVisible(
      titleFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(titleFinder, findsOneWidget);
    expect(find.text(localizations.offlineQuoteSourceTagOnly), findsOneWidget);
    expect(find.text(localizations.offlineQuoteSourceAll), findsOneWidget);

    await tester.tap(find.text(localizations.offlineQuoteSourceAll));
    await tester.pumpAndSettle();

    expect(settings.offlineQuoteSource, 'allNotes');
  });
}
