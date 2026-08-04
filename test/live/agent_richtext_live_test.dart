// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tools/propose_note_edit_tool.dart';
import 'package:thoughtecho/utils/agent_note_document_codec.dart';
import 'package:thoughtecho/utils/note_proposal_applier.dart';

import 'agent_probe.dart';

/// 第三批：富文本三种修改模式 + 提案采纳落库。
///
/// 用户点名要盯的两件事：生成的 Quill Delta 合法不合法、`content` 与
/// `deltaContent` 一不一致（AGENTS.md 硬性要求）。这两条以及「不许把媒体搞丢」
/// 都由 [ProposalCheck] 断言——它直接调生产的
/// `NoteProposalApplier.validatedArtifactOps`，和用户点「采纳」时走的是同一段。
///
/// 模型走哪种模式由它自己决定，探针只记录不强求；真正断言的是：**不管走哪条路，
/// 产出都必须能被采纳**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = AgentProbeConfig.load();
  final config = base.withModel(
    Platform.environment['TE_PROBE_MODEL'] ?? AgentProbeConfig.recommendedModel,
  );
  final tag = config.model.split(':').first;

  group('Agent 富文本与采纳（真实 API）', () {
    if (!config.isAvailable) {
      test('skipped - 未配置凭据', () {
        print('⚠️  未找到 API 密钥，跳过真实 API 探针。');
        print('   凭据文件：${AgentProbeConfig.credentialsPath}');
      });
      return;
    }

    // -- 1. insert_text：普通笔记的局部替换 -------------------------------
    test('insert_text：普通笔记局部替换，锚点唯一命中', () async {
      final original = Quote(
        id: 'note-plain',
        content: '周会记录。产品说下个版本要加协作功能，但没说清楚是多人同时编辑还是评论。'
            '我担心排期，因为现在的同步逻辑还没重构完。散会前定了下周一再对一次。',
        date: DateTime.now().toIso8601String(),
      );
      final probe = await AgentProbe.start(
        scenario: '21-insert_text-$tag',
        config: config,
        seedTags: const ['工作'],
        seedNotes: [original],
      );
      probe.transcript.notes.addAll([
        '普通（plain）笔记，用户只想动其中一句——期望走 replace + insert_text。',
        '关键不变量：改完仍是 plain（不该无故升级成 rich），锚点在全文唯一。',
      ]);

      final stored = await probe.database.getQuoteById('note-plain');
      final turn = await probe.ask(
        '把这条笔记里「我担心排期」那句改得具体一点，写清楚担心的是同步逻辑重构没完成。',
        noteContext: _contextFor(stored!),
      );

      reportTurn('insert_text', turn);
      checkProposals(turn, original: stored);
      _reportEditModes(turn);

      final proposal = _firstProposal(turn);
      if (proposal != null && proposal.resultKind == NoteDocumentKind.rich) {
        turn.findings.add('用户只要求改一句话，却把普通笔记升级成了富文本。');
      }

      await probe.finish();
      expect(turn.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 5)));

    // -- 2. insert_blocks：富文本笔记的带格式替换 -------------------------
    test('insert_blocks：富文本笔记带格式替换', () async {
      final ops = <Map<String, dynamic>>[
        {'insert': '读书笔记：深度工作'},
        {
          'insert': '\n',
          'attributes': {'header': 1}
        },
        {'insert': '作者认为深度工作是稀缺能力。以下几点我想记下来：为什么它稀缺、'},
        {'insert': '怎么练、以及它和我现在的工作方式冲突在哪。\n'},
      ];
      final original = Quote(
        id: 'note-rich',
        content: AgentNoteDocumentCodec.plainTextOf(ops),
        deltaContent: jsonEncode(ops),
        editSource: 'fullscreen',
        date: DateTime.now().toIso8601String(),
      );
      final probe = await AgentProbe.start(
        scenario: '22-insert_blocks-$tag',
        config: config,
        seedTags: const ['读书'],
        seedNotes: [original],
      );
      probe.transcript.notes.addAll([
        '这条本来就是富文本（有 h1 标题）。用户明确要求「列成清单」，'
            '期望走 insert_blocks 而不是把 Markdown 标记写进纯文本。',
        '重点看：Delta 合法、content 与 delta 还原一致、原来的 h1 没被冲掉。',
      ]);

      final stored = await probe.database.getQuoteById('note-rich');
      final turn = await probe.ask(
        '把最后那句里的三个点拆成一个带项目符号的清单，标题保留。',
        noteContext: _contextFor(stored!),
      );

      reportTurn('insert_blocks', turn);
      checkProposals(turn, original: stored);
      _reportEditModes(turn);

      final proposal = _firstProposal(turn);
      if (proposal != null) {
        final hasList = (proposal.documentOps ?? const []).any((op) {
          final attributes = op['attributes'];
          return attributes is Map && attributes['list'] != null;
        });
        if (!hasList) {
          turn.findings.add('用户要的是项目符号清单，产出的 Delta 里没有 list 属性。');
        }
        if (proposal.content.contains('- ') ||
            proposal.content.contains('* ')) {
          turn.findings.add('正文里出现了 Markdown 列表标记，说明它没用 insert_blocks。');
        }
      }

      await probe.finish();
      expect(turn.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 5)));

    // -- 3. replaceDocument：整篇重写 --------------------------------------
    test('replaceDocument：整篇重写', () async {
      final original = Quote(
        id: 'note-messy',
        content: '今天 好累 开了三个会 第一个是需求评审 后面两个想不起来了 反正没结论 '
            '晚上还要改方案 烦 明天再说吧 记一下别忘了',
        date: DateTime.now().toIso8601String(),
      );
      final probe = await AgentProbe.start(
        scenario: '23-replaceDocument-$tag',
        config: config,
        seedTags: const ['随想'],
        seedNotes: [original],
      );
      probe.transcript.notes.addAll([
        '一条流水账，用户要求整篇重写——这正是 replaceDocument 该出场的场合。',
        '工具描述要求：只有整篇重构且局部 op 明显不适用时才允许 replaceDocument，'
            '且要在 reason 里说明原因。这里顺带看它有没有照做。',
      ]);

      final stored = await probe.database.getQuoteById('note-messy');
      final turn = await probe.ask(
        '这条记得太乱了，你整篇重写一遍，分成「今天发生了什么」和「明天要做什么」两段。',
        noteContext: _contextFor(stored!),
      );

      reportTurn('replaceDocument', turn);
      checkProposals(turn, original: stored);
      _reportEditModes(turn);

      final usedReplaceDocument = _editOperations(turn)
          .any((operation) => operation['type'] == 'replaceDocument');
      final proposal = _firstProposal(turn);
      probe.transcript.notes.add(
        usedReplaceDocument
            ? '✅ 走的是 replaceDocument。'
            : 'ℹ️ 没走 replaceDocument，用局部 op 完成了整篇重写。',
      );
      if (usedReplaceDocument &&
          proposal != null &&
          proposal.reason.trim().isEmpty) {
        turn.findings.add('用了 replaceDocument 却没在 reason 里说明原因。');
      }

      await probe.finish();
      expect(turn.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 5)));

    // -- 4. 含媒体的笔记 ---------------------------------------------------
    test('含媒体：只改文字，图片一张都不能少', () async {
      final ops = <Map<String, dynamic>>[
        {'insert': '在美术馆看到的那幅画。\n'},
        {
          'insert': {'image': '/local/media/painting.jpg'}
        },
        {'insert': '\n拍的不好看 反正就是很蓝 很安静 说不上来哪里好\n'},
      ];
      final original = Quote(
        id: 'note-media',
        content: AgentNoteDocumentCodec.plainTextOf(ops),
        deltaContent: jsonEncode(ops),
        editSource: 'fullscreen',
        date: DateTime.now().toIso8601String(),
      );
      final probe = await AgentProbe.start(
        scenario: '24-含媒体-$tag',
        config: config,
        seedTags: const ['随想'],
        seedNotes: [original],
      );
      probe.transcript.notes.addAll([
        '富文本笔记中间夹着一张图片。get_note_detail 会把 embed 脱敏成 "[media]"，'
            '模型看不到真实路径。',
        '硬性要求：改完 embed 一个不能多、一个不能少（hasSameEmbeds），'
            'ProposalCheck 会断言这一条。',
      ]);

      final stored = await probe.database.getQuoteById('note-media');
      final turn = await probe.ask(
        '把图片后面那段口语化的描述改得书面一点，图片和第一句不要动。',
        noteContext: _contextFor(stored!),
      );

      reportTurn('含媒体', turn);
      // original 传进去才会校验 embed 不变。
      checkProposals(turn, original: stored);
      _reportEditModes(turn);

      final proposal = _firstProposal(turn);
      if (proposal != null && proposal.documentOps != null) {
        final embeds =
            proposal.documentOps!.where((op) => op['insert'] is! String).length;
        print('  提案里的 embed 数 = $embeds（原文 1）');
        if (embeds != 1) {
          turn.findings.add('提案里的 embed 数是 $embeds，原文是 1。');
        }
      }

      await probe.finish();
      expect(turn.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 6)));

    // -- 5. 采纳落库与重复采纳 ---------------------------------------------
    test('采纳落库：字段同步，且同一提案不能采纳两次', () async {
      final original = Quote(
        id: 'note-adopt',
        content: '晨跑第五周。配速还是上不去，但心率比刚开始低了很多。',
        date: DateTime.now().toIso8601String(),
      );
      final probe = await AgentProbe.start(
        scenario: '25-采纳落库-$tag',
        config: config,
        seedTags: const ['运动'],
        seedNotes: [original],
      );
      probe.transcript.notes.addAll([
        '走完整条链路：模型出提案 → NoteProposalApplier 落库 → 再核对库里的字段。',
        '采纳逻辑已从 _ThoughterPageState 抽到 NoteProposalApplier，'
            '所以这里跑的就是用户点「采纳」跑的那段代码。',
        '第二次采纳同一个提案必须被 revision 挡住，否则会出现重复写入。',
      ]);

      final stored = await probe.database.getQuoteById('note-adopt');
      final turn = await probe.ask(
        '帮我把这条晨跑笔记补一句：这周开始加了两次力量训练。',
        noteContext: _contextFor(stored!),
      );

      reportTurn('采纳落库', turn);
      checkProposals(turn, original: stored);

      final proposal = _firstProposal(turn);
      if (proposal == null || proposal.action != NoteProposalAction.edit) {
        turn.findings.add('没有拿到修改提案，采纳链路这一轮验不了。');
        await probe.finish();
        expect(turn.error, isNull);
        return;
      }

      final applier = NoteProposalApplier(probe.database);
      final countBefore = (await probe.database.getUserQuotes()).length;

      final first = await applier.applyEdit(proposal);
      print('  第一次采纳：${first.status.name}');
      expect(first.isApplied, isTrue, reason: '刚生成的提案必须能采纳成功');

      final saved = await probe.database.getQuoteById('note-adopt');
      expect(saved, isNotNull);
      expect(saved!.content, proposal.content, reason: '落库正文必须与提案一致');
      // content 与 deltaContent 必须同步，这是 AGENTS.md 的硬性要求。
      if (proposal.resultKind == NoteDocumentKind.rich) {
        expect(saved.deltaContent, isNotNull,
            reason: 'rich 提案落库必须带 deltaContent');
        final savedOps = AgentNoteDocumentCodec.validateAndNormalize(
          NoteDocumentKind.rich,
          jsonDecode(saved.deltaContent!),
          allowExistingEmbeds: true,
        );
        expect(
          AgentNoteDocumentCodec.plainTextOf(savedOps),
          saved.content,
          reason: '落库后的 content 与 deltaContent 不一致',
        );
      } else {
        expect(saved.deltaContent, isNull, reason: 'plain 提案不该落下 deltaContent');
      }

      // 第二次采纳同一个提案：笔记的 revision 已经变了，必须被挡住。
      final second = await applier.applyEdit(proposal);
      print('  第二次采纳：${second.status.name}');
      final countAfter = (await probe.database.getUserQuotes()).length;
      probe.transcript.notes.add(
        second.isApplied
            ? '⚠️ 同一个提案被采纳了两次！'
            : '✅ 第二次采纳被 revision 挡住（${second.status.name}）。',
      );
      if (second.isApplied) {
        turn.findings.add('同一个提案可以重复采纳，revision 没起到作用。');
      }
      expect(second.isApplied, isFalse, reason: '同一个提案不该能采纳两次');
      expect(countAfter, countBefore, reason: '采纳修改提案不该新增笔记');

      await probe.finish();
      expect(turn.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 6)));
  });
}

AgentNoteContext _contextFor(Quote quote) => AgentNoteContext(
      noteId: quote.id!,
      content: quote.content,
      documentKind: ProposeNoteEditTool.kindForQuote(quote),
      documentRevision: ProposeNoteEditTool.revisionForQuote(quote),
    );

NoteProposalArtifact? _firstProposal(ProbeTurn turn) => turn.response?.artifacts
    .whereType<NoteProposalArtifact>()
    .cast<NoteProposalArtifact?>()
    .firstWhere((_) => true, orElse: () => null);

/// `propose_note_edit` 实际提交的 operations，用来看它走了哪种模式。
List<Map<String, Object?>> _editOperations(ProbeTurn turn) => [
      for (final call in turn.toolCalls)
        if (call['tool'] == 'propose_note_edit')
          for (final operation
              in (call['arguments'] as Map?)?['operations'] as List? ??
                  const [])
            if (operation is Map)
              operation.map((key, value) => MapEntry(key.toString(), value)),
    ];

void _reportEditModes(ProbeTurn turn) {
  final operations = _editOperations(turn);
  if (operations.isEmpty) {
    print('  未提交 propose_note_edit');
    return;
  }
  final modes = operations.map((operation) {
    final type = operation['type'];
    final payload = operation.containsKey('insert_blocks')
        ? 'insert_blocks'
        : operation.containsKey('insert_text')
            ? 'insert_text'
            : '—';
    return '$type/$payload';
  }).toList();
  print('  编辑模式 $modes');
}
