// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_service.dart';

import 'agent_probe.dart';

/// 第二批：自我纠正。
///
/// 第一批（`2031880f`）已经证明**回喂给模型的错误信息质量直接决定它能不能
/// 自我纠正**——`operations` 漏 `type` 时错误是 `不支持的富文本操作: null`，
/// 模型无从下手，原样重试撞满预算，整轮失败、用户拿到 0 字。这一批把各条
/// 出错路径系统性地跑一遍，看兜底是不是都到位。
///
/// **判据是「有没有走出来」，不是「第一次就对」**：第一次填错很正常，
/// 撞满 `_maxToolFailuresPerSignature = 3` /
/// `_maxConsecutiveFailedToolRounds = 3` 整轮失败才是问题。
/// 每条都要读 transcript 里回喂给模型的那句话，看它说人话没有。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = AgentProbeConfig.load();
  final config = base.withModel(
    Platform.environment['TE_PROBE_MODEL'] ?? AgentProbeConfig.recommendedModel,
  );
  final tag = config.model.split(':').first;

  group('Agent 自我纠正（真实 API）', () {
    if (!config.isAvailable) {
      test('skipped - 未配置凭据', () {
        print('⚠️  未找到 API 密钥，跳过真实 API 探针。');
        print('   凭据文件：${AgentProbeConfig.credentialsPath}');
      });
      return;
    }

    // -- 1. 库里根本没有的主题 -------------------------------------------
    test('查无此题：老实说没找到，不要编造', () async {
      final probe = await AgentProbe.start(
        scenario: '11-查无此题-$tag',
        config: config,
        seedTags: const ['读书'],
        seedNotes: [
          Quote(
            id: 'note-reading',
            content: '《深度工作》读到第三章，知识工作者的价值取决于不可替代的深度产出。',
            date: DateTime.now()
                .subtract(const Duration(days: 5))
                .toIso8601String(),
          ),
        ],
      );
      probe.transcript.notes.addAll([
        '笔记库里只有一条读书笔记，用户问的潜水主题一条都没有。',
        '期望：如实说没找到。失败形态是编造出几条并不存在的笔记来交差。',
      ]);

      final turn = await probe.ask('我之前记过几条关于自由潜水憋气训练的笔记，帮我汇总一下要点。');

      reportTurn('查无此题', turn);
      reportRecovery(turn);

      final reply = turn.response?.content ?? '';
      if (reply.contains('潜水') &&
          !reply.contains('没有') &&
          !reply.contains('未找到') &&
          !reply.contains('没找到')) {
        turn.findings.add(
          '疑似编造：回复里谈了潜水内容却没说库里没有，需人工读一遍确认。',
        );
      }
      if (turn.response?.artifacts
              .whereType<NoteProposalArtifact>()
              .isNotEmpty ??
          false) {
        turn.findings.add('用户只是要汇总，它却提了新建笔记的提案。');
      }

      await probe.finish();
      expect(turn.error, isNull, reason: '查不到东西不该让整轮失败');
    }, timeout: const Timeout(Duration(minutes: 5)));

    // -- 2. 绑定了一个不存在的 note_id ------------------------------------
    test('note_id 不存在：改去搜索而不是原样重试', () async {
      final probe = await AgentProbe.start(
        scenario: '12-笔记不存在-$tag',
        config: config,
        seedTags: const ['随想'],
        seedNotes: [
          Quote(
            id: 'note-focus',
            content: '专注力是肌肉。每天早上第一个小时不看手机，效果最好。',
            date: DateTime.now()
                .subtract(const Duration(days: 2))
                .toIso8601String(),
          ),
        ],
      );
      probe.transcript.notes.addAll([
        '模拟编辑器绑定了一条已被删除的笔记：noteContext 的 note_id 在库里不存在。',
        'get_note_detail 会返回「未找到ID为…的笔记」，propose_note_edit 会返回'
            '「未找到指定笔记。」——期望它转去 explore_notes 找，而不是原样重试撞满预算。',
      ]);

      final turn = await probe.ask(
        '帮我把这条笔记润色一下，写得更有条理。',
        noteContext: const AgentNoteContext(
          noteId: 'note-deleted-already',
          content: '专注力是肌肉。每天早上第一个小时不看手机，效果最好。',
          documentKind: NoteDocumentKind.plain,
          documentRevision: 'stale-revision-0',
        ),
      );

      reportTurn('note_id 不存在', turn);
      reportRecovery(turn);

      final missing = turn.toolCalls
          .where((call) => call['isError'] == true)
          .where((call) =>
              call['result'].toString().contains('未找到') &&
              (call['tool'] == 'get_note_detail' ||
                  call['tool'] == 'propose_note_edit'))
          .length;
      if (missing >= 3) {
        turn.findings.add('原样重试了 $missing 次「未找到」，错误信息没能引导它换策略。');
      }
      if (!turn.toolNames.contains('explore_notes') && missing > 0) {
        turn.findings.add('拿到「未找到」后没有转去 explore_notes 搜索。');
      }

      await probe.finish();
      expect(turn.error, isNull, reason: '绑定笔记不存在不该让整轮失败');
    }, timeout: const Timeout(Duration(minutes: 5)));

    // -- 3. 两条同名标签 ---------------------------------------------------
    test('同名标签歧义：按名字定位失败后改用标签 ID', () async {
      final probe = await AgentProbe.start(
        scenario: '13-同名标签-$tag',
        config: config,
        // addTag 拒绝重名，只能用 addTagWithId 造出两条都叫「读书」的标签。
        seedTagsWithIds: const [
          (id: 'tag-reading-a', name: '读书'),
          (id: 'tag-reading-b', name: '读书'),
          (id: 'tag-work', name: '工作'),
        ],
        seedNotes: [
          Quote(
            id: 'note-reading-a',
            content: '《深度工作》：知识工作者的价值取决于不可替代的深度产出。',
            tagIds: const ['tag-reading-a'],
            date: DateTime.now()
                .subtract(const Duration(days: 5))
                .toIso8601String(),
          ),
          Quote(
            id: 'note-reading-b',
            content: '《人类简史》：农业革命是史上最大的骗局，小麦驯化了人类。',
            tagIds: const ['tag-reading-b'],
            date: DateTime.now()
                .subtract(const Duration(days: 3))
                .toIso8601String(),
          ),
          Quote(
            id: 'note-work',
            content: '下季度计划评审：优先级没排清楚。',
            tagIds: const ['tag-work'],
            date: DateTime.now().toIso8601String(),
          ),
        ],
      );
      probe.transcript.notes.addAll([
        '库里有两条同名的「读书」标签（真机上导入/同步后确实会出现）。',
        '用户按名字提，模型多半会传 tag_names:["读书"] → 走 tag_argument_resolver '
            '的歧义分支「标签名称不唯一，请改用标签 ID」。',
        '期望：调 get_tags 拿 ID 后改传 tag_ids，把两条都取到。',
      ]);

      final turn = await probe.ask('把我打了「读书」标签的笔记都找出来，一条一句话概括。');

      reportTurn('同名标签歧义', turn);
      reportRecovery(turn);

      final hitAmbiguity = turn.toolCalls.any(
        (call) => call['result'].toString().contains('标签名称不唯一'),
      );
      final usedIds = turn.toolCalls.any((call) =>
          call['tool'] == 'explore_notes' &&
          (call['arguments'] as Map?)?['tag_ids'] != null);
      probe.transcript.notes.add(
        hitAmbiguity
            ? (usedIds ? '✅ 撞到歧义后改用了 tag_ids。' : '⚠️ 撞到歧义但始终没改用 tag_ids。')
            : 'ℹ️ 这一轮没走到歧义分支（模型直接用了 ID 或换了检索方式）。',
      );
      if (hitAmbiguity && !usedIds) {
        turn.findings.add('撞到「标签名称不唯一」后没有改用 tag_ids，错误信息没指出下一步。');
      }

      await probe.finish();
      expect(turn.error, isNull, reason: '标签歧义不该让整轮失败');
    }, timeout: const Timeout(Duration(minutes: 5)));

    // -- 4. web_fetch 撞 404 ----------------------------------------------
    test('网页 404：回喂错误后换策略，不是整轮失败', () async {
      final probe = await AgentProbe.start(
        scenario: '14-网页404-$tag',
        config: config,
        seedTags: const ['随想'],
      );
      probe.transcript.notes.addAll([
        '用户直接给了一个 404 的 URL（工具描述要求 URL 只能来自用户或 web_search，'
            '所以由用户提供才是真实形态）。',
        '期望：抓取失败后如实告诉用户打不开，或改用 web_search，而不是整轮失败、'
            '也不是凭空编造网页内容。',
      ]);

      final turn = await probe.ask(
        '帮我读一下这个页面 https://example.com/thoughtecho-does-not-exist-404 '
        '然后把要点记成一条笔记。',
      );

      reportTurn('网页 404', turn);
      reportRecovery(turn);

      final fetchFailures = turn.toolCalls
          .where(
              (call) => call['tool'] == 'web_fetch' && call['isError'] == true)
          .length;
      if (fetchFailures >= 3) {
        turn.findings.add('对同一个 404 URL 重试了 $fetchFailures 次，错误信息没能让它放弃。');
      }
      final proposals =
          turn.response?.artifacts.whereType<NoteProposalArtifact>().toList() ??
              const <NoteProposalArtifact>[];
      if (proposals.isNotEmpty) {
        turn.findings.add(
          '抓取失败却仍产出了 ${proposals.length} 个提案——需人工确认内容是不是编的。',
        );
      }
      checkProposals(turn);

      await probe.finish();
      expect(turn.error, isNull, reason: '网页抓不到不该让整轮失败');
    }, timeout: const Timeout(Duration(minutes: 5)));

    // -- 5. revision 冲突 --------------------------------------------------
    test('revision 冲突：笔记被改过后重新读取再提案', () async {
      final original = Quote(
        id: 'note-conflict',
        content: '晨跑第五周。配速还是上不去，但心率比刚开始低了很多。'
            '教练说不要盯着配速，先把有氧基础打牢。',
        date:
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      );

      final probe = await AgentProbe.start(
        scenario: '15-revision冲突-$tag',
        config: config,
        seedTags: const ['运动'],
        seedNotes: [original],
      );
      probe.transcript.notes.addAll([
        'agent 会先 get_note_detail 拿 revision；探针在它拿到之后、提案之前'
            '直接改掉库里的笔记，模拟用户同时在另一个入口编辑。',
        '于是 propose_note_edit 必然带着过期 revision，撞'
            '「笔记已发生变化，请重新读取后再修改。」',
        '期望：重新 get_note_detail 再提案，而不是原样重试撞满预算。',
      ]);

      // 只在 get_note_detail 第一次返回后触发一次，正好卡在读取与提案之间。
      probe.mutateAfterTool('get_note_detail', () async {
        final stored = await probe.database.getQuoteById('note-conflict');
        if (stored == null) return;
        await probe.database.updateQuote(
          stored.copyWith(
            content: '${stored.content}\n补记：这周开始加了两次力量训练，膝盖舒服多了。',
          ),
        );
      });

      final second = await probe.ask('把我那条晨跑笔记的结尾改成一句更有力的总结，别动前面的内容。');
      reportTurn('修改（revision 中途过期）', second);
      reportRecovery(second);

      final refreshed = await probe.database.getQuoteById('note-conflict');
      checkProposals(second, original: refreshed);

      final hitConflict = second.toolCalls.any(
        (call) => call['result'].toString().contains('笔记已发生变化'),
      );
      final rereadAfterConflict = hitConflict &&
          second.toolNames.contains('get_note_detail') &&
          second.toolNames.lastIndexOf('get_note_detail') >
              second.toolNames.indexOf('propose_note_edit');
      probe.transcript.notes.add(
        hitConflict
            ? (rereadAfterConflict
                ? '✅ 撞到 revision 冲突后重新读取了笔记。'
                : '⚠️ 撞到 revision 冲突但没有重新 get_note_detail。')
            : 'ℹ️ 这一轮没走到冲突分支（模型第二轮先重新读了详情，本身是正确行为）。',
      );
      if (hitConflict && !rereadAfterConflict) {
        second.findings.add(
          '撞到「笔记已发生变化，请重新读取后再修改。」后没有重新 get_note_detail，'
          '错误信息没把「重新读取」讲成一个可执行的下一步。',
        );
      }

      await probe.finish();
      expect(second.error, isNull, reason: 'revision 冲突不该让整轮失败');
    }, timeout: const Timeout(Duration(minutes: 6)));
  });
}
