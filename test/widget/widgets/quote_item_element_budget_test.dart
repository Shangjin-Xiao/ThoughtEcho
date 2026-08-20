import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

/// 列表卡片的 **element 预算**。
///
/// 记录页的首滑卡顿有一大块就是「第一次把这张卡片建出来」：构造 widget、建
/// element 和 RenderObject。这项成本几乎与内容无关，只与卡片这棵树有多大有关，
/// 而它以前从来没有人看着 —— 直到实测发现一张**最小**卡片有 146 个 element，
/// 其中 `PopupMenuButton` 一个人占 59、心形按钮外面那层 `Tooltip` 占 10，
/// 而正文只有 3 个。
///
/// 所以这里钉一条上限。数字不是审美偏好，是首滑掉帧的直接来源：往卡片上随手加
/// 一层 `Tooltip`、一个 `IconButton`、一个 `SingleChildScrollView`，代价要乘以
/// 首滑要建的三十多张新卡片。真的需要涨，就连同「为什么值得」一起改这里。
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

const String _longChunk = '这是一段足够长的正文，用来把折叠盒撑满，好让卡片进入可展开状态。';

Future<int> _pumpAndCount(
  WidgetTester tester, {
  required Quote quote,
  Map<String, NoteTag> tagMap = const {},
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsService>.value(
      value: _FakeSettingsService(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: QuoteItemWidget(
            quote: quote,
            tagMap: tagMap,
            isExpanded: false,
            onToggleExpanded: (_) {},
            onEdit: () {},
            onDelete: () {},
            onAskAI: () {},
            onFavorite: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  var total = 0;
  void walk(Element element) {
    total++;
    element.visitChildren(walk);
  }

  walk(tester.element(find.byType(QuoteItemWidget)));
  return total;
}

Quote _quote({
  required String id,
  required String content,
  List<String> tagIds = const [],
}) =>
    Quote(
      id: id,
      content: content,
      date: DateTime(2025, 6, 21, 9).toIso8601String(),
      editSource: 'inline',
      dayPeriod: 'morning',
      tagIds: tagIds,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(QuoteItemWidget.clearExpansionCacheForTest);

  testWidgets('最小卡片（不可展开、无标签）的 element 数不超预算', (tester) async {
    // 改造前 146。
    expect(
      await _pumpAndCount(
        tester,
        quote: _quote(id: 'min', content: '短笔记'),
      ),
      lessThanOrEqualTo(100),
    );
  });

  testWidgets('可展开卡片的 element 数不超预算', (tester) async {
    // 改造前 164。可展开卡片多出折叠遮罩和两层切换动画，这是它们该有的代价。
    expect(
      await _pumpAndCount(
        tester,
        quote: _quote(
          id: 'expandable',
          content: List.filled(8, _longChunk).join('\n'),
        ),
      ),
      lessThanOrEqualTo(130),
    );
  });

  testWidgets('带标签卡片的 element 数不超预算', (tester) async {
    // 改造前 216。标签放得下时不该再挂一整个 Scrollable。
    expect(
      await _pumpAndCount(
        tester,
        quote: _quote(
          id: 'tagged',
          content: List.filled(8, _longChunk).join('\n'),
          tagIds: const ['t1', 't2', 't3'],
        ),
        tagMap: {
          't1': NoteTag(id: 't1', name: '标签一'),
          't2': NoteTag(id: 't2', name: '标签二'),
          't3': NoteTag(id: 't3', name: '标签三'),
        },
      ),
      lessThanOrEqualTo(165),
    );
  });
}
