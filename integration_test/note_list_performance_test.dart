import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

const ValueKey<String> _listKey = ValueKey<String>(
  'note_list_performance.list',
);

class _PerformanceSettingsService extends ChangeNotifier
    implements SettingsService {
  @override
  String get exportFormat => 'card';

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<String> _loadImageDataUrl() async {
  final ByteData data = await rootBundle.load('assets/icon.png');
  final Uint8List bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  return 'data:image/png;base64,${base64Encode(bytes)}';
}

List<Quote> _buildBenchmarkQuotes(String imageDataUrl) {
  return List<Quote>.generate(60, (int index) {
    final String content = '性能测试笔记 $index\n${'用于稳定复现列表滚动的长文本。' * 18}';
    if (index % 3 == 0) {
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
    if (index % 3 == 2) {
      operations.addAll(<Map<String, Object>>[
        <String, Object>{
          'insert': <String, Object>{'image': imageDataUrl},
        },
        <String, Object>{'insert': '\n图片后的说明文字\n'},
      ]);
    }

    return Quote(
      id: 'rich-$index',
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
              tagMap: const {},
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

Future<void> _runScrollSequence(WidgetTester tester) async {
  final Finder list = find.byKey(_listKey);
  for (int i = 0; i < 5; i++) {
    await tester.fling(list, const Offset(0, -900), 4200);
    await tester.pumpAndSettle();
  }
  for (int i = 0; i < 2; i++) {
    await tester.fling(list, const Offset(0, 900), 4200);
    await tester.pumpAndSettle();
  }
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(QuoteItemWidget.clearExpansionCache);

  testWidgets('exports repeatable mixed note list scrolling timeline', (
    WidgetTester tester,
  ) async {
    final String imageDataUrl = await _loadImageDataUrl();
    final List<Quote> quotes = _buildBenchmarkQuotes(imageDataUrl);

    await tester.pumpWidget(_buildBenchmarkApp(quotes));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);

    await binding.traceAction(
      () => _runScrollSequence(tester),
      reportKey: 'note_list_mixed_scroll_timeline',
    );

    final Object? rawTimeline =
        binding.reportData?['note_list_mixed_scroll_timeline'];
    if (rawTimeline is Map<String, dynamic>) {
      final Map<String, dynamic> summary = driver.TimelineSummary.summarize(
        driver.Timeline.fromJson(rawTimeline),
      ).summaryJson;
      final Map<String, dynamic> conciseSummary = <String, dynamic>{
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
      };
      debugPrint(
        'THOUGHTECHO_NOTE_LIST_PERF:${jsonEncode(conciseSummary)}',
      );
    }
  });
}
