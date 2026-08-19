import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

/// 空闲预热的全部价值在于它算出来的缓存键和卡片渲染时问的键**一模一样**。
/// 差一个像素、差一档字重，预热就变成静悄悄的空转：日志里只会看到
/// `planMiss+` / `expandMiss+` 没降，而没人知道为什么。
///
/// 这个文件钉的就是这条不变量：先暖，再真的把卡片建出来，未命中数必须一次都不涨。
/// 这个项目已经吃过一次"缓存一次都没命中"的亏（见 beab8ca），不能再吃第二次。
class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  bool get noteListDisableCardShadows => false;

  @override
  bool get noteListDisableBackdropBlur => false;

  @override
  String get exportFormat => 'card';

  @override
  String get noteCardMediaStyle => NoteCardMediaStyle.thumbnail;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

const String _longChunk = '这是一段足够长的正文，用来把折叠盒撑满，好让折叠判定和折叠排版都真的跑起来。';

Quote _plainQuote() => Quote(
      id: 'plain-1',
      content: List.filled(8, _longChunk).join('\n'),
      date: DateTime(2025, 6, 21, 9).toIso8601String(),
      editSource: 'inline',
      dayPeriod: 'morning',
    );

Quote _richQuote() => Quote(
      id: 'rich-1',
      content: List.filled(8, _longChunk).join('\n'),
      deltaContent: jsonEncode([
        for (var i = 0; i < 8; i++) {'insert': '$_longChunk\n'},
      ]),
      date: DateTime(2025, 6, 21, 9).toIso8601String(),
      editSource: 'fullscreen',
      dayPeriod: 'morning',
    );

int _planMisses() => (QuoteContent.debugCacheStats()['plan']
    as Map<String, dynamic>)['missCount'] as int;

int _expansionMisses() => (QuoteContent.debugCacheStats()['expansion']
    as Map<String, dynamic>)['missCount'] as int;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    QuoteContent.clearCacheForTesting();
    QuoteItemWidget.clearExpansionCacheForTest();
    QuoteItemWidget.lastCollapsedContentWidth = null;
  });

  Future<BuildContext> pumpCard(
    WidgetTester tester,
    Quote quote, {
    required Key key,
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: _FakeSettingsService(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return QuoteItemWidget(
                  key: key,
                  quote: quote,
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
      ),
    );
    await tester.pumpAndSettle();
    // 折叠盒对超长富文本会溢出几个像素再被 ClipRect 裁掉（改动前后一致，
    // 见 docs/note-list-first-paint-cost-2026-08-19.md 的遗留项），
    // 这里只关心缓存命中，不让它把测试带偏。
    tester.takeException();
    return captured;
  }

  for (final entry in <String, ({Quote Function() build, bool warmsPlan})>{
    '纯文本': (build: _plainQuote, warmsPlan: false),
    '富文本': (build: _richQuote, warmsPlan: true),
  }.entries) {
    testWidgets('预热过的${entry.key}卡片建出来时一次未命中都不再产生', (tester) async {
      final quote = entry.value.build();

      // 先真的建一次，拿到卡片正文区的实际布局宽度。
      final context = await pumpCard(tester, quote, key: const ValueKey('a'));
      final width = QuoteItemWidget.lastCollapsedContentWidth;
      expect(width, isNotNull, reason: '卡片建出来后必须回填正文布局宽度');
      expect(width, greaterThan(0));

      // 清空所有测量缓存，模拟"这条笔记还没被任何卡片量过"。
      QuoteContent.clearCacheForTesting();
      QuoteItemWidget.clearExpansionCacheForTest();

      QuoteItemWidget.warmCollapsedMeasurements(
        context: context,
        quote: quote,
        contentMaxWidth: width!,
        mediaStyle: NoteCardMediaStyle.thumbnail,
        prioritizeBoldContent: false,
      );

      final planMissesAfterWarmup = _planMisses();
      final expansionMissesAfterWarmup = _expansionMisses();
      expect(
        expansionMissesAfterWarmup,
        greaterThan(0),
        reason: '预热必须真的算过折叠判定，否则这个测试什么都没验证',
      );
      if (entry.value.warmsPlan) {
        expect(
          planMissesAfterWarmup,
          greaterThan(0),
          reason: '富文本的预热必须真的跑过折叠排版',
        );
      }

      // 换 key 强制整棵子树重建：折叠判定和折叠排版都会重新问一次缓存。
      await pumpCard(tester, quote, key: const ValueKey('b'));

      expect(
        _expansionMisses(),
        expansionMissesAfterWarmup,
        reason: '折叠判定的键和预热对不上',
      );
      expect(
        _planMisses(),
        planMissesAfterWarmup,
        reason: '折叠排版的键和预热对不上',
      );
    });
  }
}
