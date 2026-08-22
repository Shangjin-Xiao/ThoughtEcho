// 主题预览脚手架：把真实的 HomePage 渲染成 PNG，用来肉眼比对改动前后的观感。
//
// 它不是断言测试——`matchesGoldenFile` 只是拿来落盘的手段，一律配
// `--update-goldens` 跑。
//
// 手工风格的衬线体已经随包分发，直接从 assets 加载，不需要任何外部配置。
// 黑体（material 风格的正文和所有 label*）仍然要从环境变量
// THOUGHTECHO_PREVIEW_FONTS 指的目录取 NotoSansSC.ttf——那个没进仓库。
//
//   THOUGHTECHO_PREVIEW_FONTS=/path/to/fonts \
//     flutter test --update-goldens test/preview/theme_preview_test.dart
//
// 不给字体目录也能跑，只是 material 风格那几张图画不出中文。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/home_page.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/clipboard_service.dart';
import 'package:thoughtecho/services/connectivity_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/excerpt_intent_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';

import '../test_harness.dart';
// 只取 mock，不要把那边的 main 一起带进来。
import '../widget/pages/home_page_test.dart'
    show
        MockAIService,
        MockClipboardService,
        MockConnectivityService,
        MockDatabaseService,
        MockExcerptIntentService,
        MockFeatureGuideService,
        MockInsightHistoryService,
        MockLocationService,
        MockSearchController,
        MockSmartPushService,
        MockSettingsService,
        MockWeatherService;

/// 注入一条固定的一言，让前后两轮渲染可以逐像素对比。
///
/// 走本地一言这条路：mock 的 `useLocalQuotesOnly` 为 true，`ApiService` 会直接
/// 问 `getLocalDailyQuote`，拿不到才去随机挑一条内置默认句——**随机就意味着
/// 改前改后两张图的正文不一样**，对比就没法看了。这里给死一条。
///
/// 注意不要试图从 `SmartPushService` 那条「通知待展示」的路注入：
/// `consumePendingDailyQuoteForHomeDisplay` 是定义在 extension 上的，
/// 扩展方法按**静态类型**解析，`implements` 覆盖不掉，注入不会生效。
class PreviewDatabaseService extends MockDatabaseService {
  @override
  Future<Map<String, dynamic>?> getLocalDailyQuote({
    String offlineQuoteSource = 'tagOnly',
  }) async =>
      <String, dynamic>{
        'content': '予力众生，成就不凡。',
        'source': 'Microsoft',
        'author': '',
        'type': 'local',
        'from_who': '',
        'from': 'Microsoft',
        'provider': 'local',
      };
}

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

Future<void> _loadPreviewFonts(String? dir) async {
  // 手工风格的衬线体随包分发，直接从仓库里的产物加载，不依赖外部字体目录。
  await _loadFont(
    ThemeStyleForm.bundledSerif,
    ThemeStyleForm.bundledSerifAsset,
  );
  // 测试环境的默认族，label* 和 material 风格的正文都落在它上面。黑体没进仓库。
  if (dir != null) await _loadFont('Roboto', '$dir/NotoSansSC.ttf');
  // 图标字体不在测试环境里，不加载的话满屏都是空心方块。
  // 从 Flutter SDK 缓存直接取，不进仓库。
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    await _loadFont(
      'MaterialIcons',
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  }
}

void main() {
  final fontDir = Platform.environment['THOUGHTECHO_PREVIEW_FONTS'];

  setUpAll(() async {
    await TestHarness.initialize();
    await _loadPreviewFonts(fontDir);
  });

  Future<void> renderHome(
    WidgetTester tester, {
    required ThemeStyle style,
    required ThemeAccent accent,
    required Brightness brightness,
    required String name,
  }) async {
    // 逻辑尺寸按常见直板机取：393 × 873，dpr 2。
    tester.view.physicalSize = const Size(786, 1746);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 没跑 initialize()，内部 _storage 为 null，两个 setter 会在落盘前 return，
    // 只留内存中的取值——正是预览要的。
    final appTheme = AppTheme();
    await appTheme.setThemeStyle(style);
    await appTheme.setThemeAccent(accent);

    await tester.pumpWidget(
      RepaintBoundary(
        child: MultiProvider(
          providers: [
            Provider<bool>.value(value: true),
            ChangeNotifierProvider<AppTheme>.value(value: appTheme),
            ChangeNotifierProvider<SmartPushService>.value(
                value: MockSmartPushService()),
            ChangeNotifierProvider<FeatureGuideService>.value(
                value: MockFeatureGuideService()),
            ChangeNotifierProvider<ClipboardService>.value(
                value: MockClipboardService()),
            ChangeNotifierProvider<InsightHistoryService>.value(
                value: MockInsightHistoryService()),
            ChangeNotifierProvider<DatabaseService>.value(
                value: PreviewDatabaseService()),
            ChangeNotifierProvider<SettingsService>.value(
                value: MockSettingsService()),
            ChangeNotifierProvider<NoteSearchController>.value(
                value: MockSearchController()),
            ChangeNotifierProvider<ConnectivityService>.value(
                value: MockConnectivityService()),
            ChangeNotifierProvider<AIService>.value(value: MockAIService()),
            ChangeNotifierProvider<LocationService>.value(
                value: MockLocationService()),
            ChangeNotifierProvider<WeatherService>.value(
                value: MockWeatherService()),
            Provider<ExcerptIntentService>.value(
                value: MockExcerptIntentService()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            theme: appTheme.createLightThemeData(),
            darkTheme: appTheme.createDarkThemeData(),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: const HomePage(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('images/$name.png'),
    );
  }

  testWidgets('首页 · 纸与墨 · 赭石 · 亮色', (tester) async {
    await renderHome(
      tester,
      style: ThemeStyle.paper,
      accent: ThemeAccent.umber,
      brightness: Brightness.light,
      name: 'home_paper_umber_light',
    );
  }, skip: fontDir == null);

  testWidgets('首页 · 素笺 · 黛青 · 亮色', (tester) async {
    await renderHome(
      tester,
      style: ThemeStyle.plain,
      accent: ThemeAccent.celadon,
      brightness: Brightness.light,
      name: 'home_plain_celadon_light',
    );
  }, skip: fontDir == null);

  testWidgets('首页 · 纸与墨 · 赭石 · 暗色', (tester) async {
    await renderHome(
      tester,
      style: ThemeStyle.paper,
      accent: ThemeAccent.umber,
      brightness: Brightness.dark,
      name: 'home_paper_umber_dark',
    );
  }, skip: fontDir == null);

  testWidgets('首页 · Material · 亮色', (tester) async {
    await renderHome(
      tester,
      style: ThemeStyle.material,
      accent: ThemeAccent.umber,
      brightness: Brightness.light,
      name: 'home_material_light',
    );
  }, skip: fontDir == null);
}
