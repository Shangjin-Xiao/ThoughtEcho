import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/utils/quill_editor_extensions.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

import 'support/layout_probe.dart';
import 'support/timeline_slice_extractor.dart';

const ValueKey<String> _listKey = ValueKey<String>(
  'note_list_performance.list',
);
const ValueKey<String> _openAddNoteKey = ValueKey<String>(
  'note_list_performance.open_add_note',
);
const String _resultChunkPrefix = 'THOUGHTECHO_PERF_CHUNK:';

enum _ListScenario { plainText, richText, images }

class _PerformanceSettingsService extends ChangeNotifier
    implements SettingsService {
  final AppSettings _settings = AppSettings.defaultSettings().copyWith(
    developerMode: true,
    enableFirstOpenScrollPerfMonitor: true,
  );

  @override
  AppSettings get appSettings => _settings;

  @override
  bool get addNoteDialogAutoFocus => _settings.addNoteDialogAutoFocus;

  @override
  bool get addNoteDialogDeferAutoMetadata =>
      _settings.addNoteDialogDeferAutoMetadata;

  @override
  bool get autoAttachLocation => _settings.autoAttachLocation;

  @override
  bool get autoAttachWeather => _settings.autoAttachWeather;

  @override
  String? get defaultAuthor => _settings.defaultAuthor;

  @override
  String? get defaultSource => _settings.defaultSource;

  @override
  List<String> get defaultTagIds => _settings.defaultTagIds;

  @override
  bool get enableFirstOpenScrollPerfMonitor => true;

  @override
  String get exportFormat => 'card';

  @override
  LocalAISettings get localAISettings => LocalAISettings.defaultSettings();

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PerformanceFeatureGuideService extends FeatureGuideService {
  _PerformanceFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;
}

class _PerformanceDatabaseService extends DatabaseService {
  _PerformanceDatabaseService(this.quotes) : super.forTesting();

  final List<Quote> quotes;

  @override
  bool get isInitialized => true;

  @override
  bool get hasMoreQuotes => false;

  @override
  Future<List<NoteCategory>> getCategories() async => const <NoteCategory>[];

  @override
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
  }) async {}

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
  }) {
    return Stream<List<Quote>>.value(quotes);
  }
}

Future<List<String>> _prepareImageFilePaths({
  String namespace = 'standard',
}) async {
  final List<String> paths = <String>[
    'assets/large_test_1.jpg',
    'assets/large_test_2.jpg',
    'assets/large_test_3.jpg',
    'assets/large_test_4.jpg',
    'assets/large_test_5.jpg',
  ];
  final Directory directory = Directory(
    '${(await getTemporaryDirectory()).path}/thoughtecho-performance-images/'
    '$namespace',
  );
  await directory.create(recursive: true);
  return Future.wait(
    paths.map((String path) async {
      final ByteData data = await rootBundle.load(path);
      final File file = File(
        '${directory.path}/${path.substring(path.lastIndexOf('/') + 1)}',
      );
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return file.path;
    }),
  );
}

List<Quote> _buildBenchmarkQuotes(
  _ListScenario scenario,
  List<String> imageDataUrls,
) {
  return List<Quote>.generate(60, (int index) {
    final String content = '性能测试笔记 $index\n${'用于稳定复现列表滚动的长文本。' * 18}';
    if (scenario == _ListScenario.plainText) {
      return Quote(
        id: 'plain-$index',
        content: content,
        date: DateTime(2026, 6, 7, 8, index).toIso8601String(),
        editSource: 'inline',
      );
    }

    final List<Map<String, Object>> operations = <Map<String, Object>>[];
    if (scenario == _ListScenario.images) {
      operations.addAll(<Map<String, Object>>[
        <String, Object>{
          'insert': <String, Object>{
            'image': imageDataUrls[index % imageDataUrls.length],
          },
        },
        <String, Object>{'insert': '\n'},
      ]);
    }
    operations.addAll(<Map<String, Object>>[
      <String, Object>{
        'insert': '富文本性能测试标题 $index',
        'attributes': <String, Object>{'bold': true},
      },
      <String, Object>{'insert': '\n$content\n'},
    ]);

    return Quote(
      id: '${scenario.name}-$index',
      content: content,
      deltaContent: jsonEncode(operations),
      date: DateTime(2026, 6, 7, 8, index).toIso8601String(),
      editSource: 'fullscreen',
    );
  });
}

Widget _buildBenchmarkApp(
  List<Quote> quotes, {
  bool probeItemLayouts = false,
}) {
  return ChangeNotifierProvider<SettingsService>.value(
    value: _PerformanceSettingsService(),
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: ListView.builder(
          key: _listKey,
          addSemanticIndexes: false,
          scrollCacheExtent: const ScrollCacheExtent.pixels(800),
          itemCount: quotes.length,
          itemBuilder: (BuildContext context, int index) {
            final Widget item = QuoteItemWidget(
              key: ValueKey<String>('benchmark-quote-$index'),
              quote: quotes[index],
              tagMap: const <String, NoteCategory>{},
              isExpanded: false,
              onToggleExpanded: (_) {},
              onEdit: () {},
              onDelete: () {},
              onAskAI: () {},
            );
            if (!probeItemLayouts) {
              return item;
            }
            return DiagnosticLayoutProbe(
              index: index,
              kind: quotes[index].deltaContent == null
                  ? 'plainText'
                  : quotes[index].deltaContent!.contains('"image"')
                      ? 'images'
                      : 'richText',
              child: item,
            );
          },
        ),
      ),
    ),
  );
}

Widget _buildRealNoteListBenchmarkApp(List<Quote> quotes) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DatabaseService>.value(
        value: _PerformanceDatabaseService(quotes),
      ),
      ChangeNotifierProvider<SettingsService>.value(
        value: _PerformanceSettingsService(),
      ),
      ChangeNotifierProvider<NoteSearchController>(
        create: (_) => NoteSearchController(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: NoteListView(
          key: _listKey,
          tags: const <NoteCategory>[],
          selectedTagIds: const <String>[],
          onTagSelectionChanged: (_) {},
          searchQuery: '',
          sortType: 'time',
          sortAscending: false,
          onSortChanged: (_, __) {},
          onSearchChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onAskAI: (_) {},
          selectedWeathers: const <String>[],
          selectedDayPeriods: const <String>[],
          onFilterChanged: (_, __) {},
        ),
      ),
    ),
  );
}

Widget _buildAddNoteBenchmarkApp() {
  final List<NoteCategory> tags = List<NoteCategory>.generate(
    100,
    (int index) => NoteCategory(
      id: 'tag-$index',
      name: '性能标签 $index',
      iconName: index.isEven ? 'tag' : 'star',
    ),
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(
        value: _PerformanceSettingsService(),
      ),
      ChangeNotifierProvider<FeatureGuideService>.value(
        value: _PerformanceFeatureGuideService(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => FilledButton(
            key: _openAddNoteKey,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              sheetAnimationStyle: AddNoteDialog.bottomSheetAnimationStyle,
              requestFocus: false,
              builder: (BuildContext context) => AddNoteDialog(
                tags: tags,
                onSave: (_) {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _runScrollSequence(WidgetTester tester, String scenario) async {
  final Finder list = _findBenchmarkListScrollable();
  for (int i = 0; i < 5; i++) {
    final developer.TimelineTask flingTask = developer.TimelineTask(
      filterKey: 'ThoughtEcho',
    )..start(
        'ThoughtEcho.NoteList.fling',
        arguments: <String, Object>{
          'scenario': scenario,
          'direction': 'down',
          'iteration': i,
        },
      );
    await tester.fling(list, const Offset(0, -900), 4200);
    await tester.pumpAndSettle();
    flingTask.finish();
  }
  for (int i = 0; i < 2; i++) {
    final developer.TimelineTask flingTask = developer.TimelineTask(
      filterKey: 'ThoughtEcho',
    )..start(
        'ThoughtEcho.NoteList.fling',
        arguments: <String, Object>{
          'scenario': scenario,
          'direction': 'up',
          'iteration': i,
        },
      );
    await tester.fling(list, const Offset(0, 900), 4200);
    await tester.pumpAndSettle();
    flingTask.finish();
  }
}

Future<void> _runDiagnosticScrollSequence(
  WidgetTester tester,
  String scenario,
) async {
  final Finder list = _findBenchmarkListScrollable();
  final developer.TimelineTask flingTask = developer.TimelineTask(
    filterKey: 'ThoughtEcho',
  )..start(
      'ThoughtEcho.NoteList.diagnosticFling',
      arguments: <String, Object>{'scenario': scenario},
    );
  await tester.fling(list, const Offset(0, -900), 4200);
  await tester.pumpAndSettle();
  flingTask.finish();
}

Future<void> _runDiagnosticImageScrollSequence(
  WidgetTester tester,
  String scenario,
) async {
  isListScrolling.value = false;
  await tester.pump(const Duration(milliseconds: 250));
  await _runDiagnosticScrollSequence(tester, scenario);
}

void _jumpListToStart(WidgetTester tester) {
  final ScrollableState scrollable = tester.state<ScrollableState>(
    _findBenchmarkListScrollable(),
  );
  scrollable.position.jumpTo(0);
}

Finder _findBenchmarkListScrollable() {
  final keyedRoot = find.byKey(_listKey);
  final listViews = find.descendant(
    of: keyedRoot,
    matching: find.byType(ListView),
  );
  final listView =
      listViews.evaluate().isNotEmpty ? listViews.first : keyedRoot;
  return find
      .descendant(
        of: listView,
        matching: find.byType(Scrollable),
      )
      .first;
}

Map<String, dynamic> _diagnosticSummary(
  String scenario,
  Map<String, dynamic> rawTimeline,
) {
  final driver.Timeline timeline = driver.Timeline.fromJson(rawTimeline);
  final Map<String, dynamic> summary =
      driver.TimelineSummary.summarize(timeline).summaryJson;
  final List<dynamic> events =
      rawTimeline['traceEvents'] as List<dynamic>? ?? <dynamic>[];
  final Map<String, double> slowestSlices = <String, double>{};
  final Map<String, int> customEventCounts = <String, int>{};
  final List<({String name, double timestampMicros})> customEvents =
      <({String name, double timestampMicros})>[];
  final List<Map<String, dynamic>> slowSlices = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> itemInitialSizes = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> itemSizeChanges = <Map<String, dynamic>>[];

  for (final dynamic rawEvent in events) {
    if (rawEvent is! Map<String, dynamic>) {
      continue;
    }
    final String name = rawEvent['name']?.toString() ?? '';
    if (name.startsWith('ThoughtEcho.')) {
      customEventCounts[name] = (customEventCounts[name] ?? 0) + 1;
      final Object? timestamp = rawEvent['ts'];
      if (timestamp is num) {
        customEvents.add((
          name: name,
          timestampMicros: timestamp.toDouble(),
        ));
      }
    }
    if (name == 'NoteListItemSizeChanged' ||
        name == 'ThoughtEcho.NoteListView.itemSizeChanged') {
      final Map<String, dynamic> sizeEvent = <String, dynamic>{
        if (rawEvent['args'] is Map<String, dynamic>)
          ...rawEvent['args'] as Map<String, dynamic>,
        if (rawEvent['ts'] is num)
          'timestamp_us': (rawEvent['ts'] as num).toDouble(),
      };
      if (sizeEvent['oldHeight'] == 'none') {
        itemInitialSizes.add(sizeEvent);
      } else {
        itemSizeChanges.add(sizeEvent);
      }
    }
  }

  for (final Map<String, dynamic> slice in extractTimelineSlices(events)) {
    final String name = slice['name'] as String;
    final double millis = (slice['duration_us'] as double) / 1000;
    if (slice['kind'] == 'asynchronous') {
      continue;
    }
    if (millis > (slowestSlices[name] ?? 0)) {
      slowestSlices[name] = double.parse(millis.toStringAsFixed(2));
    }
    if (millis >= 8) {
      slowSlices.add(<String, dynamic>{
        'name': name,
        if (slice['category'] != null) 'category': slice['category'],
        if (slice['thread_id'] != null) 'thread_id': slice['thread_id'],
        if (slice['arguments'] != null) 'arguments': slice['arguments'],
        'duration_ms': double.parse(millis.toStringAsFixed(2)),
        'timestamp_us': slice['timestamp_us'],
      });
    }
  }

  slowSlices.sort(
    (Map<String, dynamic> a, Map<String, dynamic> b) =>
        (b['duration_ms'] as double).compareTo(a['duration_ms'] as double),
  );
  final List<Map<String, dynamic>> correlatedSlowSlices =
      slowSlices.take(16).map((Map<String, dynamic> slice) {
    final double timestamp = slice['timestamp_us'] as double;
    if (customEvents.isEmpty) {
      return slice..remove('timestamp_us');
    }
    final ({String name, double timestampMicros}) nearest = customEvents.reduce(
      (
        ({String name, double timestampMicros}) current,
        ({String name, double timestampMicros}) candidate,
      ) =>
          (candidate.timestampMicros - timestamp).abs() <
                  (current.timestampMicros - timestamp).abs()
              ? candidate
              : current,
    );
    return slice
      ..remove('timestamp_us')
      ..['nearest_marker'] = nearest.name
      ..['marker_delta_ms'] = double.parse(
        ((timestamp - nearest.timestampMicros) / 1000).toStringAsFixed(2),
      );
  }).toList();
  final List<Map<String, dynamic>> itemLayoutSlices = extractTimelineSlices(
    events,
  ).where((Map<String, dynamic> slice) {
    return slice['name'] == 'NoteListItemLayout' ||
        slice['name'] == 'ThoughtEcho.NoteListView.itemLayout';
  }).map((Map<String, dynamic> slice) {
    return <String, dynamic>{
      'duration_ms': double.parse(
        ((slice['duration_us'] as double) / 1000).toStringAsFixed(2),
      ),
      if (slice['arguments'] != null) 'arguments': slice['arguments'],
    };
  }).toList()
    ..sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (b['duration_ms'] as double).compareTo(a['duration_ms'] as double),
    );
  final List<Map<String, dynamic>> itemBuildSlices = extractTimelineSlices(
    events,
  ).where((Map<String, dynamic> slice) {
    return slice['name'] == 'ThoughtEcho.NoteListView.itemBuilder';
  }).map((Map<String, dynamic> slice) {
    return <String, dynamic>{
      'duration_ms': double.parse(
        ((slice['duration_us'] as double) / 1000).toStringAsFixed(2),
      ),
      if (slice['arguments'] != null) 'arguments': slice['arguments'],
    };
  }).toList()
    ..sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (b['duration_ms'] as double).compareTo(a['duration_ms'] as double),
    );
  final List<MapEntry<String, double>> slowestEntries =
      slowestSlices.entries.toList()
        ..sort(
          (MapEntry<String, double> a, MapEntry<String, double> b) =>
              b.value.compareTo(a.value),
        );
  final Map<String, double> topSlowestSlices = <String, double>{
    for (final MapEntry<String, double> entry in slowestEntries.take(30))
      entry.key: entry.value,
  };

  return <String, dynamic>{
    'scenario': scenario,
    'trace_event_count': events.length,
    'duration_slice_name_count': slowestSlices.length,
    for (final String key in <String>[
      'frame_count',
      '90th_percentile_frame_build_time_millis',
      '99th_percentile_frame_build_time_millis',
      'worst_frame_build_time_millis',
      'missed_frame_build_budget_count',
      '90th_percentile_frame_rasterizer_time_millis',
      '99th_percentile_frame_rasterizer_time_millis',
      'worst_frame_rasterizer_time_millis',
      'missed_frame_rasterizer_budget_count',
      'new_gen_gc_count',
      'old_gen_gc_count',
    ])
      if (summary.containsKey(key)) key: summary[key],
    'slowest_slices_ms': topSlowestSlices,
    'correlated_slow_slices': correlatedSlowSlices,
    if (itemLayoutSlices.isNotEmpty)
      'slowest_item_layouts': itemLayoutSlices.take(20).toList(),
    if (itemBuildSlices.isNotEmpty)
      'slowest_item_builds': itemBuildSlices.take(20).toList(),
    if (itemInitialSizes.isNotEmpty)
      'item_initial_sizes': itemInitialSizes.take(100).toList(),
    if (itemSizeChanges.isNotEmpty)
      'item_size_changes': itemSizeChanges.take(100).toList(),
    'custom_event_counts': customEventCounts,
  };
}

Future<void> _traceDetailedRichTextScenario(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
) async {
  await _traceDetailedScenario(
    binding,
    'note_list_richText_diagnostic',
    () => _runDiagnosticScrollSequence(tester, 'richText_diagnostic'),
  );
}

Future<void> _traceDetailedScenario(
  IntegrationTestWidgetsFlutterBinding binding,
  String scenario,
  Future<void> Function() action,
) async {
  debugProfileBuildsEnabled = true;
  debugProfileLayoutsEnabled = true;
  debugEnhanceBuildTimelineArguments = true;
  debugEnhanceLayoutTimelineArguments = true;
  try {
    await _traceScenario(binding, scenario, action);
  } finally {
    debugProfileBuildsEnabled = false;
    debugProfileLayoutsEnabled = false;
    debugEnhanceBuildTimelineArguments = false;
    debugEnhanceLayoutTimelineArguments = false;
  }
}

Future<void> _traceDetailedFlatVisualScenario(
  IntegrationTestWidgetsFlutterBinding binding,
  String scenario,
  Future<void> Function() action,
) async {
  QuoteItemWidget.disableVisualEffectsForTesting = true;
  try {
    await _traceDetailedScenario(binding, scenario, action);
  } finally {
    QuoteItemWidget.disableVisualEffectsForTesting = false;
  }
}

Future<void> _traceScenario(
  IntegrationTestWidgetsFlutterBinding binding,
  String scenario,
  Future<void> Function() action,
) async {
  final String reportKey = 'thoughtecho_$scenario';
  await binding.traceAction(action, reportKey: reportKey);
  final Object? rawTimeline = binding.reportData?[reportKey];
  if (rawTimeline is Map<String, dynamic>) {
    final String encoded = base64Encode(
      utf8.encode(jsonEncode(_diagnosticSummary(scenario, rawTimeline))),
    );
    for (int offset = 0, chunk = 0; offset < encoded.length; chunk++) {
      final int end = (offset + 700).clamp(0, encoded.length);
      debugPrint(
        '$_resultChunkPrefix$scenario:$chunk:${encoded.substring(offset, end)}',
      );
      offset = end;
    }
  }
}

Future<void> _openAddNoteDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(_openAddNoteKey));
  await tester.pumpAndSettle();
  expect(find.byType(AddNoteDialog), findsOneWidget);
  // Keep the trace open through deferred metadata and the fallback lifecycle
  // timeout when the cloud device does not expose a software keyboard.
  await tester.pump(const Duration(milliseconds: 2500));
  await tester.pumpAndSettle();
}

Future<void> _closeAddNoteDialog(WidgetTester tester) async {
  final BuildContext context = tester.element(find.byType(AddNoteDialog));
  Navigator.pop(context);
  await tester.pumpAndSettle();
  expect(find.byType(AddNoteDialog), findsNothing);
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    QuoteItemWidget.disableVisualEffectsForTesting = false;
    QuoteItemWidget.clearExpansionCache();
  });

  testWidgets('exports segmented note-list and add-note performance timelines',
      (
    WidgetTester tester,
  ) async {
    for (final _ListScenario scenario in <_ListScenario>[
      _ListScenario.plainText,
      _ListScenario.richText,
    ]) {
      await tester.pumpWidget(
        _buildBenchmarkApp(_buildBenchmarkQuotes(scenario, const <String>[])),
      );
      await tester.pumpAndSettle();
      _jumpListToStart(tester);
      await tester.pumpAndSettle();
      await _traceScenario(
        binding,
        'note_list_${scenario.name}',
        () => _runScrollSequence(tester, scenario.name),
      );
      if (scenario == _ListScenario.richText) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        QuoteContent.resetCaches();
        QuoteItemWidget.clearExpansionCache();
        await tester.pumpWidget(
          _buildBenchmarkApp(
            _buildBenchmarkQuotes(_ListScenario.richText, const <String>[]),
            probeItemLayouts: true,
          ),
        );
        await tester.pumpAndSettle();
        _jumpListToStart(tester);
        await tester.pumpAndSettle();
        await _traceDetailedRichTextScenario(binding, tester);
      }
    }

    final List<String> imageDataUrls = await _prepareImageFilePaths();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.pumpWidget(
      _buildBenchmarkApp(
        _buildBenchmarkQuotes(_ListScenario.images, imageDataUrls),
      ),
    );
    await tester.pumpAndSettle();
    _jumpListToStart(tester);
    await tester.pumpAndSettle();
    expect(
      find.byType(Image),
      findsWidgets,
      reason: 'Image scenario must render visible images before tracing.',
    );
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await _traceScenario(
      binding,
      'note_list_images_cold',
      () => _runScrollSequence(tester, 'images_cold'),
    );
    _jumpListToStart(tester);
    await tester.pumpAndSettle();
    await _traceScenario(
      binding,
      'note_list_images_warm',
      () => _runScrollSequence(tester, 'images_warm'),
    );

    final List<String> diagnosticImagePaths = await _prepareImageFilePaths(
      namespace: 'diagnostic',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    QuoteContent.resetCaches();
    QuoteItemWidget.clearExpansionCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    isListScrolling.value = true;
    await tester.pumpWidget(
      _buildBenchmarkApp(
        _buildBenchmarkQuotes(_ListScenario.images, diagnosticImagePaths),
        probeItemLayouts: true,
      ),
    );
    await tester.pump();
    try {
      await _traceDetailedScenario(
        binding,
        'note_list_images_cold_diagnostic',
        () => _runDiagnosticImageScrollSequence(
          tester,
          'images_cold_diagnostic',
        ),
      );
    } finally {
      isListScrolling.value = false;
    }
    _jumpListToStart(tester);
    await tester.pumpAndSettle();
    await _traceDetailedScenario(
      binding,
      'note_list_images_warm_diagnostic',
      () => _runDiagnosticScrollSequence(tester, 'images_warm_diagnostic'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    QuoteContent.resetCaches();
    QuoteItemWidget.clearExpansionCache();
    await tester.pumpWidget(
      _buildRealNoteListBenchmarkApp(
        _buildBenchmarkQuotes(_ListScenario.richText, const <String>[]),
      ),
    );
    await tester.pumpAndSettle();
    _jumpListToStart(tester);
    await tester.pumpAndSettle();
    await _traceDetailedScenario(
      binding,
      'real_note_list_richText_diagnostic',
      () => _runDiagnosticScrollSequence(
        tester,
        'real_richText_diagnostic',
      ),
    );
    _jumpListToStart(tester);
    await tester.pumpAndSettle();
    await _traceDetailedFlatVisualScenario(
      binding,
      'real_note_list_richText_flatVisual_diagnostic',
      () => _runDiagnosticScrollSequence(
        tester,
        'real_richText_flatVisual_diagnostic',
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    QuoteContent.resetCaches();
    QuoteItemWidget.clearExpansionCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    isListScrolling.value = true;
    await tester.pumpWidget(
      _buildRealNoteListBenchmarkApp(
        _buildBenchmarkQuotes(_ListScenario.images, diagnosticImagePaths),
      ),
    );
    await tester.pump();
    try {
      await _traceDetailedScenario(
        binding,
        'real_note_list_images_cold_diagnostic',
        () => _runDiagnosticImageScrollSequence(
          tester,
          'real_images_cold_diagnostic',
        ),
      );
    } finally {
      isListScrolling.value = false;
    }
    _jumpListToStart(tester);
    await tester.pumpAndSettle();
    await _traceDetailedFlatVisualScenario(
      binding,
      'real_note_list_images_flatVisual_diagnostic',
      () => _runDiagnosticScrollSequence(
        tester,
        'real_images_flatVisual_diagnostic',
      ),
    );

    imageDataUrls.clear();
    diagnosticImagePaths.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.pumpWidget(_buildAddNoteBenchmarkApp());
    await tester.pumpAndSettle();
    await _traceScenario(
      binding,
      'add_note_dialog_cold_open',
      () => _openAddNoteDialog(tester),
    );
    await _closeAddNoteDialog(tester);
    await _traceScenario(
      binding,
      'add_note_dialog_warm_open',
      () => _openAddNoteDialog(tester),
    );
    await _closeAddNoteDialog(tester);
    await tester.pumpWidget(_buildAddNoteBenchmarkApp());
    await tester.pumpAndSettle();
    await _traceDetailedScenario(
      binding,
      'add_note_dialog_cold_diagnostic_open',
      () => _openAddNoteDialog(tester),
    );
    await _closeAddNoteDialog(tester);
    await _traceDetailedScenario(
      binding,
      'add_note_dialog_warm_diagnostic_open',
      () => _openAddNoteDialog(tester),
    );
    await _closeAddNoteDialog(tester);
  });
}
