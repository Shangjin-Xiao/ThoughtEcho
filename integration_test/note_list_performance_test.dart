import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

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
  final AppSettings _settings = AppSettings.defaultSettings();

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
  bool get enableFirstOpenScrollPerfMonitor =>
      _settings.enableFirstOpenScrollPerfMonitor;

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

Future<List<String>> _loadImageDataUrls() async {
  final List<String> paths = <String>[
    'assets/large_test_1.jpg',
    'assets/large_test_2.jpg',
    'assets/large_test_3.jpg',
    'assets/large_test_4.jpg',
    'assets/large_test_5.jpg',
  ];
  return Future.wait(
    paths.map((String path) async {
      final ByteData data = await rootBundle.load(path);
      final Uint8List bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
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

    final List<Map<String, Object>> operations = <Map<String, Object>>[
      <String, Object>{
        'insert': '富文本性能测试标题 $index',
        'attributes': <String, Object>{'bold': true},
      },
      <String, Object>{'insert': '\n$content\n'},
    ];
    if (scenario == _ListScenario.images) {
      operations.addAll(<Map<String, Object>>[
        <String, Object>{
          'insert': <String, Object>{
            'image': imageDataUrls[index % imageDataUrls.length],
          },
        },
        <String, Object>{'insert': '\n图片后的说明文字\n'},
      ]);
    }

    return Quote(
      id: '${scenario.name}-$index',
      content: content,
      deltaContent: jsonEncode(operations),
      date: DateTime(2026, 6, 7, 8, index).toIso8601String(),
      editSource: 'fullscreen',
    );
  });
}

Widget _buildBenchmarkApp(List<Quote> quotes) {
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
            return QuoteItemWidget(
              key: ValueKey<String>('benchmark-quote-$index'),
              quote: quotes[index],
              tagMap: const <String, NoteCategory>{},
              isExpanded: false,
              onToggleExpanded: (_) {},
              onEdit: () {},
              onDelete: () {},
              onAskAI: () {},
            );
          },
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
  final Finder list = find.byKey(_listKey);
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
    if (const <String>{
      'Frame',
      'BUILD',
      'LAYOUT',
      'SEMANTICS',
      'GPURasterizer::Draw',
      'DartIsolate::HandleMessage',
    }.contains(name)) {
      final Object? duration = rawEvent['dur'];
      if (duration is num) {
        final double millis = duration.toDouble() / 1000;
        if (millis > (slowestSlices[name] ?? 0)) {
          slowestSlices[name] = millis;
        }
        final Object? timestamp = rawEvent['ts'];
        if (millis >= 8 && timestamp is num) {
          slowSlices.add(<String, dynamic>{
            'name': name,
            'duration_ms': double.parse(millis.toStringAsFixed(2)),
            'timestamp_us': timestamp.toDouble(),
          });
        }
      }
    }
  }

  slowSlices.sort(
    (Map<String, dynamic> a, Map<String, dynamic> b) =>
        (b['duration_ms'] as double).compareTo(a['duration_ms'] as double),
  );
  final List<Map<String, dynamic>> correlatedSlowSlices =
      slowSlices.take(8).map((Map<String, dynamic> slice) {
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

  return <String, dynamic>{
    'scenario': scenario,
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
    'slowest_slices_ms': slowestSlices,
    'correlated_slow_slices': correlatedSlowSlices,
    'custom_event_counts': customEventCounts,
  };
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

  tearDown(QuoteItemWidget.clearExpansionCache);

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
      await _traceScenario(
        binding,
        'note_list_${scenario.name}',
        () => _runScrollSequence(tester, scenario.name),
      );
    }

    final List<String> imageDataUrls = await _loadImageDataUrls();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.pumpWidget(
      _buildBenchmarkApp(
        _buildBenchmarkQuotes(_ListScenario.images, imageDataUrls),
      ),
    );
    await tester.pumpAndSettle();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await _traceScenario(
      binding,
      'note_list_images_cold',
      () => _runScrollSequence(tester, 'images_cold'),
    );
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(_listKey),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    await _traceScenario(
      binding,
      'note_list_images_warm',
      () => _runScrollSequence(tester, 'images_warm'),
    );

    imageDataUrls.clear();
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
  });
}
