import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/ai/note_proposal_card.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';

class _Settings extends ChangeNotifier implements SettingsService {
  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _app(Widget child) => ChangeNotifierProvider<SettingsService>.value(
      value: _Settings(),
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets('edit proposal shows badge and final document without diff',
      (tester) async {
    final artifact = NoteProposalArtifact(
      action: NoteProposalAction.edit,
      proposalTitle: 'Polish',
      reason: 'Clearer wording',
      noteId: 'note',
      originalKind: NoteDocumentKind.plain,
      resultKind: NoteDocumentKind.rich,
      modeTransition: NoteModeTransition.plainToRich,
      content: 'Final document',
      documentOps: const [
        {'insert': 'Final document\n'}
      ],
      metadata: const {},
      changes: [
        NoteProposalChange(type: 'replace', before: 'Old', after: 'Final'),
      ],
      baseRevision: 'revision',
    );

    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: artifact,
      onOpenInEditor: () async {},
      onApply: () async => 'note-id',
    )));

    expect(find.byType(QuoteContent), findsOneWidget);
    // 卡头动作徽章：修改
    expect(find.text('修改'), findsOneWidget);
    // 设计终版：不显示理由行与修改记录（diff）
    expect(find.text('Clearer wording'), findsNothing);
    expect(find.text('查看修改记录'), findsNothing);
    expect(find.text('Old'), findsNothing);
    expect(find.textContaining('全屏富文本编辑器'), findsOneWidget);
  });

  testWidgets('limits long document height and shows view-note after save',
      (tester) async {
    final artifact = NoteProposalArtifact(
      action: NoteProposalAction.create,
      proposalTitle: 'Draft',
      reason: '',
      resultKind: NoteDocumentKind.plain,
      content: List.filled(100, 'long text').join('\n'),
      documentOps: null,
      metadata: const {},
      changes: const [],
    );
    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: artifact,
      onOpenInEditor: () async {},
      onApply: () async => 'note-id',
      onViewNote: (_) {},
    )));

    // 卡头动作徽章：新建
    expect(find.text('新建'), findsOneWidget);
    final constrained = tester.widgetList<ConstrainedBox>(
      find.byType(ConstrainedBox),
    );
    expect(
      constrained.any((widget) => widget.constraints.maxHeight == 220),
      isTrue,
    );
    await tester.tap(find.text('保存笔记'));
    await tester.pumpAndSettle();
    expect(find.text('已保存 · 查看笔记'), findsOneWidget);
  });

  testWidgets('short content hides the expand toggle, long content keeps it',
      (tester) async {
    NoteProposalArtifact build(String content) => NoteProposalArtifact(
          action: NoteProposalAction.create,
          proposalTitle: 'Draft',
          reason: '',
          resultKind: NoteDocumentKind.plain,
          content: content,
          documentOps: null,
          metadata: const {},
          changes: const [],
        );

    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: build('一句话'),
      onOpenInEditor: () async {},
      onApply: () async => 'note-id',
    )));
    await tester.pumpAndSettle();
    expect(find.text('展开全文'), findsNothing);

    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: build(List.filled(100, '很长的正文').join('\n')),
      onOpenInEditor: () async {},
      onApply: () async => 'note-id',
    )));
    await tester.pumpAndSettle();
    expect(find.text('展开全文'), findsOneWidget);
    await tester.tap(find.text('展开全文'));
    await tester.pumpAndSettle();
    expect(find.text('收起全文'), findsOneWidget);
  });

  testWidgets('create proposal shows location/weather chips and reports toggle',
      (tester) async {
    bool? location;
    bool? weather;
    final artifact = NoteProposalArtifact(
      action: NoteProposalAction.create,
      proposalTitle: 'Draft',
      reason: '',
      resultKind: NoteDocumentKind.plain,
      content: 'content',
      documentOps: null,
      metadata: const {'include_location': true},
      changes: const [],
    );

    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: artifact,
      onOpenInEditor: () async {},
      onApply: () async => 'note-id',
      locationPreview: '杭州市',
      weatherPreview: '晴 26℃',
      onMetadataChanged: (includeLocation, includeWeather) {
        location = includeLocation;
        weather = includeWeather;
      },
    )));
    await tester.pumpAndSettle();

    // 已缓存的位置/天气直接显示（同步读取，不阻塞卡片渲染）
    expect(find.text('杭州市'), findsOneWidget);
    expect(find.text('晴 26℃'), findsOneWidget);
    final locationChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '杭州市'),
    );
    expect(locationChip.selected, isTrue);

    await tester.ensureVisible(find.text('晴 26℃'));
    await tester.tap(find.text('晴 26℃'));
    await tester.pumpAndSettle();
    expect(location, isTrue);
    expect(weather, isTrue);
  });

  testWidgets('weather chip fetches on tap and reverts when fetch fails',
      (tester) async {
    var resolveCalls = 0;
    String? resolved;
    final artifact = NoteProposalArtifact(
      action: NoteProposalAction.create,
      proposalTitle: 'Draft',
      reason: '',
      resultKind: NoteDocumentKind.plain,
      content: 'content',
      documentOps: null,
      metadata: const {},
      changes: const [],
    );

    Widget card() => NoteProposalCard(
          artifact: artifact,
          onOpenInEditor: () async {},
          onApply: () async => 'note-id',
          onResolveWeather: () async {
            resolveCalls++;
            return resolved;
          },
        );

    // 获取失败：开关回退为未勾选
    await tester.pumpWidget(_app(card()));
    await tester.ensureVisible(find.text('天气'));
    await tester.tap(find.text('天气'));
    await tester.pumpAndSettle();
    expect(resolveCalls, 1);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '天气')).selected,
      isFalse,
    );

    // 获取成功：胶囊显示现场获取到的天气
    resolved = '多云 18℃';
    await tester.ensureVisible(find.text('天气'));
    await tester.tap(find.text('天气'));
    await tester.pumpAndSettle();
    expect(resolveCalls, 2);
    expect(find.text('多云 18℃'), findsOneWidget);
  });

  testWidgets('collapsed content cannot be scrolled, expanded content can',
      (tester) async {
    final artifact = NoteProposalArtifact(
      action: NoteProposalAction.create,
      proposalTitle: 'Draft',
      reason: '',
      resultKind: NoteDocumentKind.plain,
      content: List.filled(100, '很长的正文').join('\n'),
      documentOps: null,
      metadata: const {},
      changes: const [],
    );
    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: artifact,
      onOpenInEditor: () async {},
      onApply: () async => 'note-id',
    )));
    await tester.pumpAndSettle();

    SingleChildScrollView contentScrollView() => tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .firstWhere((view) => view.controller != null);

    expect(
      contentScrollView().physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    await tester.tap(find.text('展开全文'));
    await tester.pumpAndSettle();
    expect(contentScrollView().physics, isA<ClampingScrollPhysics>());
  });

  testWidgets('quick edit chip invokes callback and hides when readOnly',
      (tester) async {
    NoteProposalQuickEdit? received;
    final artifact = NoteProposalArtifact(
      action: NoteProposalAction.create,
      proposalTitle: 'Draft',
      reason: '',
      resultKind: NoteDocumentKind.plain,
      content: 'content',
      documentOps: null,
      metadata: const {
        'author': '作者',
        'tag_ids': ['t1']
      },
      changes: const [],
    );

    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: artifact,
      onOpenInEditor: () async {},
      onApply: () async => 'note-id',
      onQuickEdit: (current) async {
        received = current;
        return null;
      },
    )));
    await tester.tap(find.widgetWithText(ActionChip, '快编'));
    await tester.pump();
    expect(received?.author, '作者');
    expect(received?.tagIds, ['t1']);

    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: NoteProposalArtifact(
        action: NoteProposalAction.create,
        proposalTitle: 'Draft',
        reason: '',
        resultKind: NoteDocumentKind.plain,
        content: 'content',
        documentOps: null,
        metadata: const {},
        changes: const [],
        readOnly: true,
      ),
      onOpenInEditor: () async {},
      onApply: () async => 'note-id',
      onQuickEdit: (current) async => null,
    )));
    await tester.pump();
    expect(find.text('快编'), findsNothing);
  });
}
