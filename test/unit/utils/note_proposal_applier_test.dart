import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_tools/propose_note_edit_tool.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/utils/agent_note_document_codec.dart';
import 'package:thoughtecho/utils/note_proposal_applier.dart';

import '../../test_harness.dart';

/// 采纳提案的落库不变量。
///
/// 这段逻辑原本长在 `_ThoughterPageState` 里跑不动，抽成 [NoteProposalApplier]
/// 之后才有这个文件。真实 API 那侧的覆盖在
/// `test/live/agent_richtext_live_test.dart`，这里只锁确定性行为。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService database;

  setUp(() async {
    await TestHarness.initialize();
    database = DatabaseService();
    await database.init();
    for (final quote in await database.getAllQuotes(includeDeleted: true)) {
      final id = quote.id;
      if (id != null) await database.permanentlyDeleteQuote(id);
    }
  });

  Future<Quote> seed(Quote quote) async {
    await database.addQuote(quote);
    return (await database.getQuoteById(quote.id!))!;
  }

  NoteProposalArtifact editArtifact({
    required Quote original,
    required String content,
    List<Map<String, dynamic>>? documentOps,
    String? baseRevision,
    Map<String, Object?> metadata = const {},
  }) =>
      NoteProposalArtifact(
        action: NoteProposalAction.edit,
        proposalTitle: '测试提案',
        reason: '测试',
        noteId: original.id,
        originalKind: ProposeNoteEditTool.kindForQuote(original),
        resultKind: documentOps == null
            ? NoteDocumentKind.plain
            : NoteDocumentKind.rich,
        content: content,
        documentOps: documentOps,
        metadata: metadata,
        changes: const [],
        baseRevision:
            baseRevision ?? ProposeNoteEditTool.revisionForQuote(original),
      );

  test('采纳普通笔记提案：正文落库，不留下 deltaContent', () async {
    final original = await seed(Quote(
      id: 'note-plain',
      content: '原始正文。',
      date: DateTime.now().toIso8601String(),
    ));

    final result = await NoteProposalApplier(database).applyEdit(
      editArtifact(original: original, content: '改过的正文。'),
    );

    expect(result.isApplied, isTrue);
    final saved = await database.getQuoteById('note-plain');
    expect(saved!.content, '改过的正文。');
    expect(saved.deltaContent, isNull);
  });

  test('采纳富文本提案：content 与 deltaContent 必须一致', () async {
    final original = await seed(Quote(
      id: 'note-rich',
      content: '原始正文。',
      date: DateTime.now().toIso8601String(),
    ));
    final ops = <Map<String, dynamic>>[
      {'insert': '新标题'},
      {
        'insert': '\n',
        'attributes': {'header': 1}
      },
      {'insert': '正文段落。\n'},
    ];

    final result = await NoteProposalApplier(database).applyEdit(
      editArtifact(
        original: original,
        content: AgentNoteDocumentCodec.plainTextOf(ops),
        documentOps: ops,
      ),
    );

    expect(result.isApplied, isTrue);
    final saved = await database.getQuoteById('note-rich');
    expect(saved!.deltaContent, isNotNull);
    expect(saved.editSource, 'fullscreen');
    final savedOps = AgentNoteDocumentCodec.validateAndNormalize(
      NoteDocumentKind.rich,
      jsonDecode(saved.deltaContent!),
      allowExistingEmbeds: true,
    );
    expect(AgentNoteDocumentCodec.plainTextOf(savedOps), saved.content);
  });

  test('同一个提案不能采纳两次', () async {
    final original = await seed(Quote(
      id: 'note-twice',
      content: '原始正文。',
      date: DateTime.now().toIso8601String(),
    ));
    final artifact = editArtifact(original: original, content: '改过的正文。');
    final applier = NoteProposalApplier(database);
    final countBefore = (await database.getUserQuotes()).length;

    expect((await applier.applyEdit(artifact)).isApplied, isTrue);

    final second = await applier.applyEdit(artifact);
    expect(second.status, NoteProposalApplyStatus.conflict);
    final saved = await database.getQuoteById('note-twice');
    expect(saved!.content, '改过的正文。', reason: '第二次采纳不该再动笔记');
    expect(
      (await database.getUserQuotes()).length,
      countBefore,
      reason: '采纳修改提案不该新增笔记',
    );
  });

  test('笔记在提案之后被改过：拒绝落库', () async {
    final original = await seed(Quote(
      id: 'note-stale',
      content: '原始正文。',
      date: DateTime.now().toIso8601String(),
    ));
    final artifact = editArtifact(
      original: original,
      content: '改过的正文。',
      baseRevision: 'stale-revision',
    );

    final result = await NoteProposalApplier(database).applyEdit(artifact);

    expect(result.status, NoteProposalApplyStatus.conflict);
    expect((await database.getQuoteById('note-stale'))!.content, '原始正文。');
  });

  test('提案增删媒体时校验直接拒绝', () async {
    final ops = <Map<String, dynamic>>[
      {'insert': '图注。\n'},
      {
        'insert': {'image': '/local/media/a.jpg'}
      },
      {'insert': '\n'},
    ];
    final original = await seed(Quote(
      id: 'note-media',
      content: AgentNoteDocumentCodec.plainTextOf(ops),
      deltaContent: jsonEncode(ops),
      editSource: 'fullscreen',
      date: DateTime.now().toIso8601String(),
    ));
    // 把图片抹掉的提案。
    final withoutMedia = <Map<String, dynamic>>[
      {'insert': '图注。\n'},
    ];

    expect(
      () => NoteProposalApplier.validatedArtifactOps(
        editArtifact(
          original: original,
          content: AgentNoteDocumentCodec.plainTextOf(withoutMedia),
          documentOps: withoutMedia,
        ),
        original: original,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
