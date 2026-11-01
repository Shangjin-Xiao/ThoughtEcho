import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/draft_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get autoAttachLocation => false;

  @override
  bool get autoAttachWeather => false;

  @override
  String? get defaultAuthor => null;

  @override
  String? get defaultSource => null;

  @override
  List<String> get defaultTagIds => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocationService extends ChangeNotifier implements LocationService {
  @override
  bool get hasLocationPermission => false;

  @override
  bool get isLocationServiceEnabled => false;

  @override
  String? get currentPoiName => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWeatherService extends ChangeNotifier implements WeatherService {
  @override
  bool get hasData => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDatabaseService extends ChangeNotifier implements DatabaseService {
  _TestDatabaseService({this.fullQuote});

  final Quote? fullQuote;

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    return fullQuote;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFeatureGuideService extends FeatureGuideService {
  _TestFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}

  @override
  Future<void> resetGuide(String guideId) async {}

  @override
  Future<void> resetAllGuides() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DraftService draftService;
  late MMKVService mmkvService;

  setUpAll(() async {
    await TestHarness.initialize();
    await MMKVService().init();
  });

  setUp(() async {
    draftService = DraftService();
    mmkvService = MMKVService();
    await mmkvService.clear();
  });

  tearDown(() async {
    //
  });

  testWidgets('全屏编辑器 NoteFullEditorPage 注册 _OptimizedImageEmbedBuilder 作为图片构建器',
      (WidgetTester tester) async {
    final mockSettings = _TestSettingsService();
    final mockLocation = _TestLocationService();
    final mockWeather = _TestWeatherService();
    final mockDatabase = _TestDatabaseService();
    final mockGuide = _TestFeatureGuideService();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: mockSettings),
          ChangeNotifierProvider<LocationService>.value(value: mockLocation),
          ChangeNotifierProvider<WeatherService>.value(value: mockWeather),
          ChangeNotifierProvider<DatabaseService>.value(value: mockDatabase),
          ChangeNotifierProvider<FeatureGuideService>.value(value: mockGuide),
          Provider<DraftService>.value(value: draftService),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: NoteFullEditorPage(
            initialContent: '测试正文',
            allTags: [],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final quillEditorFinder = find.byType(QuillEditor);
    expect(quillEditorFinder, findsOneWidget);

    final editorWidget = tester.widget<QuillEditor>(quillEditorFinder);
    final imageBuilder = editorWidget.config.embedBuilders?.firstWhere(
      (builder) => builder.key == 'image',
    );

    expect(
      imageBuilder?.runtimeType.toString(),
      '_OptimizedImageEmbedBuilder',
      reason: '全屏编辑器必须使用 _OptimizedImageEmbedBuilder 进行图片解码优化',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('全屏编辑器加载包含图片的富文本时渲染优化图片组件并隔离重绘', (WidgetTester tester) async {
    final imageDelta = jsonEncode([
      {"insert": "图文笔记测试\n"},
      {
        "insert": {"image": "https://example.com/sample_image.png"}
      },
      {"insert": "\n"}
    ]);

    final quoteWithImage = Quote(
      id: 'quote-with-image-1',
      content: '图文笔记测试\n',
      deltaContent: imageDelta,
      date: DateTime.now().toIso8601String(),
    );

    final mockSettings = _TestSettingsService();
    final mockLocation = _TestLocationService();
    final mockWeather = _TestWeatherService();
    final mockDatabase = _TestDatabaseService(fullQuote: quoteWithImage);
    final mockGuide = _TestFeatureGuideService();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: mockSettings),
          ChangeNotifierProvider<LocationService>.value(value: mockLocation),
          ChangeNotifierProvider<WeatherService>.value(value: mockWeather),
          ChangeNotifierProvider<DatabaseService>.value(value: mockDatabase),
          ChangeNotifierProvider<FeatureGuideService>.value(value: mockGuide),
          Provider<DraftService>.value(value: draftService),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: NoteFullEditorPage(
            initialContent: quoteWithImage.content,
            initialQuote: quoteWithImage,
            allTags: const [],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final quillEditorFinder = find.byType(QuillEditor);
    expect(quillEditorFinder, findsOneWidget);

    // 验证富文本中的图片节点存在且有 RepaintBoundary 进行重绘隔离
    expect(find.byType(RepaintBoundary), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
