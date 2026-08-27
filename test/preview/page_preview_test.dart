// 记录页 / 设置页的预览脚手架。和 `theme_preview_test.dart` 是同一路数——
// `matchesGoldenFile` 只是落盘手段，一律配 `--update-goldens` 跑，不是断言测试。
//
//   THOUGHTECHO_PREVIEW_FONTS=/path/to/fonts \
//     flutter test --update-goldens test/preview/page_preview_test.dart
//
// 为什么单独开一个文件而不是往 `theme_preview_test.dart` 里塞：那边只渲首页，
// 用的是空数据库；这里要的是**装着真实笔记的记录页**——排版问题（字重、字号、
// 元信息和正文的主次）只有在一张卡同时出现日期、正文、来源、标签的时候才看得见。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
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
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';

import '../test_harness.dart';
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

/// 三条固定笔记，覆盖记录页卡片上会出现的每一种文字：
/// 日期 + 时段、位置、天气温度（都是 `bodySmall`）、正文（`bodyLarge`）、
/// 来源（`bodyMedium`）、标签胶囊（`labelSmall`）、心形计数。
///
/// **内容必须写死**，随机或者「今天」这类相对值会让改前改后两张图没法逐像素比。
///
/// **一律用公有领域的古诗词和虚构地点，不要放任何真实用户的笔记或署名。**
/// 这是公开仓库，预览夹具会长期留在仓库里，图也可能贴进 PR 和 issue。
/// 挑诗词还有个额外好处：它天然带作者 + 作品两段来源，正好把 `bodyMedium`
/// 那一级喂满，而三条长短不同（1 行 / 2 行 / 3 行）能同时看到折行和卡片高度。
final _previewQuotes = <Quote>[
  Quote(
    id: 'p1',
    content: '莫听穿林打叶声，何妨吟啸且徐行。竹杖芒鞋轻胜马，谁怕？',
    date: '2026-08-23T18:30:00.000',
    dayPeriod: 'dusk',
    location: '杭州市·西湖区',
    weather: 'drizzle',
    temperature: '28°C',
    sourceAuthor: '苏轼',
    sourceWork: '定风波·莫听穿林打叶声',
    tagIds: const ['t_essay'],
  ),
  Quote(
    id: 'p2',
    content: '两情若是久长时，又岂在朝朝暮暮',
    date: '2026-08-20T21:10:00.000',
    dayPeriod: 'night',
    location: '杭州市·西湖区',
    weather: 'cloudy',
    temperature: '26°C',
    sourceAuthor: '秦观',
    sourceWork: '鹊桥仙·纤云弄巧',
    tagIds: const ['t_essay', 't_poem'],
  ),
  Quote(
    id: 'p3',
    content: '昨夜雨疏风骤，浓睡不消残酒。\n试问卷帘人，却道海棠依旧。\n知否，知否？应是绿肥红瘦。',
    date: '2026-08-13T22:05:00.000',
    dayPeriod: 'night',
    location: '杭州市·西湖区',
    weather: 'partly_cloudy',
    temperature: '29°C',
    sourceAuthor: '李清照',
    sourceWork: '如梦令',
    tagIds: const ['t_poem'],
    favoriteCount: 1,
  ),
];

final _previewTags = <NoteTag>[
  NoteTag(id: 't_essay', name: '随记', icon: '📝'),
  NoteTag(id: 't_poem', name: '诗词', icon: '🪶'),
];

class PreviewDatabaseService extends MockDatabaseService {
  @override
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool includeDeleted = false,
  }) =>
      Stream.value(_previewQuotes);

  @override
  Future<List<Quote>> getAllQuotes({
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async =>
      _previewQuotes;

  @override
  Future<List<NoteTag>> getTags() async => _previewTags;

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

/// `MockSettingsService` 是给首页写的，记录页和设置页会多问它两项。
/// 补在这里而不是改那边：那个 mock 被十几个用例共用，动它等于动它们的输入。
/// 这一组几乎都是「照搬 AppSettings 的默认值」——真身也是这么读的
/// （`_appSettings.xxx`），所以从 [appSettings] 转发就等于拿到出厂设置。
class PreviewSettingsService extends MockSettingsService {
  @override
  bool get showExactTime => appSettings.showExactTime;
  @override
  bool get showNoteEditTime => appSettings.showNoteEditTime;
  @override
  int get trashRetentionDays => appSettings.trashRetentionDays;
  @override
  String? get trashRetentionLastModified => null;
  @override
  String get noteCardMediaStyle => appSettings.noteCardMediaStyle;
  @override
  bool get noteListDisableCardShadows => appSettings.noteListDisableCardShadows;
  @override
  bool get noteListDisableBackdropBlur =>
      appSettings.noteListDisableBackdropBlur;
  @override
  bool get enableFirstOpenScrollPerfMonitor =>
      appSettings.enableFirstOpenScrollPerfMonitor;
  @override
  bool get addNoteDialogAutoFocus => appSettings.addNoteDialogAutoFocus;
  @override
  bool get addNoteDialogDeferAutoMetadata =>
      appSettings.addNoteDialogDeferAutoMetadata;
  @override
  bool get enableHiddenNotes => appSettings.enableHiddenNotes;
  @override
  bool get requireBiometricForHidden => appSettings.requireBiometricForHidden;
  @override
  bool get autoAttachLocation => appSettings.autoAttachLocation;
  @override
  bool get autoAttachWeather => appSettings.autoAttachWeather;
  @override
  bool get sentryEnabled => appSettings.sentryEnabled;
  @override
  bool get useLocalQuotesOnly => appSettings.useLocalQuotesOnly;
  @override
  String get exportFormat => appSettings.exportFormat;
  // 下面这几项真身是从 MMKV 读的，没有 AppSettings 背书，给默认值即可。
  @override
  bool get syncSkipConfirm => false;
  @override
  bool get syncDefaultIncludeMedia => true;
  @override
  bool get dontShowAgentExperimentalNotice => false;
  @override
  bool get agentMemoryEnabled => true;
  @override
  bool get agentMemoryNoticeShown => true;
  @override
  String get userNickname => '';
}

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

/// 黑体按字重逐档加载。
///
/// `label*` 和（#519 之后的）`bodySmall` 都落在黑体上，而胶囊、导航栏标签、
/// 筛选态各自用的字重并不相同。只加载一个 Regular 的话，引擎会给 w500/w600
/// 合成伪粗体——**那正好会盖掉这套图要看的东西**（元信息到底比正文轻多少）。
/// 目录里有 `NotoSansSC-{400,500,600,700}.ttf` 就逐档加载，只有单份
/// `NotoSansSC.ttf` 也能跑，粗细档次会失真。
Future<void> _loadSans(String? dir) async {
  if (dir == null) return;
  var loadedAny = false;
  for (final weight in [400, 500, 600, 700]) {
    final path = '$dir/NotoSansSC-$weight.ttf';
    if (File(path).existsSync()) {
      await _loadFont('Roboto', path);
      loadedAny = true;
    }
  }
  if (!loadedAny) await _loadFont('Roboto', '$dir/NotoSansSC.ttf');
}

Future<void> _loadPreviewFonts(String? dir) async {
  await _loadFont(
    ThemeStyleForm.bundledSerif,
    ThemeStyleForm.bundledSerifAsset,
  );
  await _loadSans(dir);
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
  // 出图前缀，用来在同一棵工作树上区分「改动前 / 改动后」两轮。
  final tag = Platform.environment['THOUGHTECHO_PREVIEW_TAG'] ?? 'current';
  final outDir =
      Platform.environment['THOUGHTECHO_PREVIEW_OUT'] ?? 'test/preview/images';

  setUpAll(() async {
    await TestHarness.initialize();
    await _loadPreviewFonts(fontDir);
  });

  /// 渲染 HomePage 的某个 tab。
  ///
  /// 走**点导航栏**而不是直接构造子页面：记录页和设置页都挂在 `IndexedStack`
  /// 里，脱离 HomePage 单独 pump 就没有底部导航栏、没有 FAB、没有 AppBar——
  /// 那正是要一起看的东西。
  Future<void> renderTab(
    WidgetTester tester, {
    required ThemeStyle style,
    required ThemeAccent accent,

    /// null 表示留在默认的首页——首页那个 destination 已经是选中态，
    /// 未选中图标 `home_outlined` 根本不在树里，点不到。
    required IconData? navIcon,

    /// 亮暗两套都要出图：手工风格的字重/字号在暗色下压在深底上，观感和亮色
    /// 不是一回事，只渲亮色等于半边没看。
    Brightness brightness = Brightness.light,
    required String name,
  }) async {
    tester.view.physicalSize = const Size(786, 1746);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                value: PreviewSettingsService()),
            // 设置页有一段 Consumer<WebDAVSyncService>。它是个单例
            // ChangeNotifier，构造私有、没法 mock，直接把真身挂上去——
            // 预览不碰同步，只要它能被 read 到就够了。
            ChangeNotifierProvider<WebDAVSyncService>.value(
                value: WebDAVSyncService()),
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

    if (navIcon != null) {
      await tester.tap(find.byIcon(navIcon));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
    }

    // 不走 `matchesGoldenFile`：它内部的 `captureImage` 把 pixelRatio 写死成 1，
    // 出来的图就是 393×873 的逻辑像素——**字重和笔画粗细正好在这个分辨率下看不出来**，
    // 而这套图就是拿来看这个的。自己抓 layer，按 3× 落盘。
    final renderObject =
        find.byType(RepaintBoundary).first.evaluate().single.renderObject!;
    final layer = renderObject.debugLayer! as OffsetLayer;
    // **整段必须裹在 `runAsync` 里。** `toImage` / `toByteData` 是真正的平台异步，
    // 在 widget 测试的 fake-async 时区里发起，图能出来（各几十毫秒），但测试主体
    // 之后再也等不到收尾——每个用例都要空转到 10 分钟超时才往下走。
    // `matchesGoldenFile` 内部也是这么裹的。
    await tester.runAsync(() async {
      final image =
          await layer.toImage(renderObject.paintBounds, pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory(outDir)..createSync(recursive: true);
      final suffix = brightness == Brightness.dark ? '_dark' : '';
      File('${dir.path}/${tag}_$name$suffix.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  for (final (styleName, style, accent) in [
    ('paper', ThemeStyle.paper, ThemeAccent.umber),
    ('material', ThemeStyle.material, ThemeAccent.umber),
  ]) {
    testWidgets('记录页 · $styleName', (tester) async {
      await renderTab(
        tester,
        style: style,
        accent: accent,
        navIcon: Icons.book_outlined,
        name: 'notes_$styleName',
      );
    }, skip: fontDir == null);

    testWidgets('设置页 · $styleName', (tester) async {
      await renderTab(
        tester,
        style: style,
        accent: accent,
        navIcon: Icons.settings_outlined,
        name: 'settings_$styleName',
      );
    }, skip: fontDir == null);

    testWidgets('首页 · $styleName', (tester) async {
      await renderTab(
        tester,
        style: style,
        accent: accent,
        navIcon: null,
        name: 'home_$styleName',
      );
    }, skip: fontDir == null);

    testWidgets('记录页 · $styleName · 暗色', (tester) async {
      await renderTab(
        tester,
        style: style,
        accent: accent,
        navIcon: Icons.book_outlined,
        name: 'notes_$styleName',
        brightness: Brightness.dark,
      );
    }, skip: fontDir == null);

    testWidgets('首页 · $styleName · 暗色', (tester) async {
      await renderTab(
        tester,
        style: style,
        accent: accent,
        navIcon: null,
        name: 'home_$styleName',
        brightness: Brightness.dark,
      );
    }, skip: fontDir == null);
  }
}
