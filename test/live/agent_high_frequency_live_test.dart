// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tools/propose_note_edit_tool.dart';

import 'agent_probe.dart';

/// 第一批：用户高频场景的真实 API 探针。
///
/// 三条路径分别对应 App 里最常走的三个入口：
///   1. 对话里让 Thoughter 生成一条笔记
///   2. 让它改笔记库里已有的笔记
///   3. 从编辑器打开、绑定当前笔记做润色
///
/// 探针为主：模型行为只记录不断言，只有 Delta 合法性与
/// content/deltaContent 一致这类确定性不变量才断言。
/// transcript 落在 `build/agent-probe/*.md`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 默认跑推荐模型；对照其他模型时用 TE_PROBE_MODEL 覆盖，
  // transcript 文件名带上模型，两份结果不会互相覆盖。
  final base = AgentProbeConfig.load();
  final config = base.withModel(
    Platform.environment['TE_PROBE_MODEL'] ?? AgentProbeConfig.recommendedModel,
  );
  final tag = config.model.split(':').first;

  group('Agent 高频场景（真实 API）', () {
    if (!config.isAvailable) {
      test('skipped - 未配置凭据', () {
        print('⚠️  未找到 API 密钥，跳过真实 API 探针。');
        print('   凭据文件：${AgentProbeConfig.credentialsPath}');
        print('   或设置 TE_TEST_API_KEY 环境变量。');
      });
      return;
    }

    // -- 场景 1：让它生成一条笔记 ---------------------------------------
    test('生成笔记：从模糊请求到可采纳的提案', () async {
      final probe = await AgentProbe.start(
        scenario: '01-生成笔记-$tag',
        config: config,
        seedTags: const ['读书', '随想'],
        seedNotes: [
          Quote(
            id: 'seed-reading',
            content: '《人类简史》里说农业革命是史上最大的骗局，小麦驯化了人类而不是相反。',
            date: DateTime.now()
                .subtract(const Duration(days: 3))
                .toIso8601String(),
          ),
        ],
      );
      probe.transcript.notes.addAll([
        '模拟用户在对话里直接说「帮我记一下」，请求刻意模糊。',
        'system prompt 期望它先调 get_location_weather / explore_notes / get_tags '
            '建立上下文再动笔，这里观察它实际是不是这么做的。',
      ]);

      final turn = await probe.ask(
        '帮我记一下：今天下午在咖啡馆想到，专注力其实是一种可以训练的肌肉，'
        '而不是天生的性格。你帮我整理成一条笔记吧，格式好看点。',
      );

      reportTurn('生成笔记', turn);
      checkProposals(turn);

      await probe.finish();

      expect(turn.error, isNull, reason: '高频路径不应整轮抛异常');
    }, timeout: const Timeout(Duration(minutes: 5)));

    // -- 场景 2：改笔记库里已有的笔记 ------------------------------------
    test('改已有笔记：先找到再改，并观察跨轮记忆', () async {
      final probe = await AgentProbe.start(
        scenario: '02-改已有笔记-$tag',
        config: config,
        seedTags: const ['读书', '工作'],
        seedNotes: [
          Quote(
            id: 'note-focus',
            content: '专注力是肌肉。每天早上第一个小时不看手机，效果最好。'
                '但周末总是破功，可能是因为没有外部约束。',
            date: DateTime.now()
                .subtract(const Duration(days: 2))
                .toIso8601String(),
          ),
          Quote(
            id: 'note-reading',
            content: '《深度工作》读到第三章。作者说知识工作者的价值取决于'
                '不可替代的深度产出，而不是可见的忙碌。这一点对我触动很大，'
                '因为我过去一直用「在线时长」证明自己在工作。',
            date: DateTime.now()
                .subtract(const Duration(days: 5))
                .toIso8601String(),
          ),
          Quote(
            id: 'note-misc',
            content: '买牛奶、还书、周五之前交报销。',
            date: DateTime.now()
                .subtract(const Duration(days: 1))
                .toIso8601String(),
          ),
        ],
      );
      probe.transcript.notes.addAll([
        '用户不给 note_id，只给模糊描述，agent 必须先 explore_notes 定位。',
        '第二轮是追问，用来验证 75f7d9d4（工具轨迹进历史）：'
            '如果它又调一次 explore_notes，说明轨迹没起作用。',
      ]);

      final first = await probe.ask(
        '我之前记过一条关于专注力的笔记，你帮我把它扩写一下，'
        '把周末破功那部分展开说说可能的原因。',
      );
      reportTurn('改已有笔记', first);
      checkProposals(first);

      final second = await probe.ask('你刚才查到的那几条笔记里，哪一条最长？');
      reportTurn('追问（跨轮记忆）', second);

      final firstExplored = first.toolNames.contains('explore_notes');
      final secondExplored = second.toolNames.contains('explore_notes');
      if (firstExplored && secondExplored) {
        second.findings.add(
          '跨轮记忆存疑：第二轮又调了一次 explore_notes，'
          '说明工具轨迹没进历史或模型没在用（对照 75f7d9d4）。',
        );
      } else if (firstExplored && !secondExplored) {
        probe.transcript.notes.add('✅ 跨轮记忆生效：第二轮直接依据上一轮轨迹作答。');
      }

      await probe.finish();

      expect(first.error, isNull, reason: '高频路径不应整轮抛异常');
    }, timeout: const Timeout(Duration(minutes: 6)));

    // -- 场景 3：从编辑器打开润色 ----------------------------------------
    test('编辑器润色：绑定当前笔记，局部改写不跑偏', () async {
      final original = Quote(
        id: 'note-editing',
        content: '今天开会讲了下季度计划。反正就是要做很多事，'
            '时间很紧，大家都很忙。我觉得优先级没排清楚，'
            '这样下去容易什么都做不完。',
        date: DateTime.now().toIso8601String(),
      );

      final probe = await AgentProbe.start(
        scenario: '03-编辑器润色-$tag',
        config: config,
        seedTags: const ['工作'],
        seedNotes: [original],
      );
      probe.transcript.notes.addAll([
        '模拟从编辑器唤起：noteContext 已绑定当前笔记，'
            'agent 不需要再去搜索就该知道要改哪一条。',
        '重点看它是否直接 propose_note_edit，以及文本锚点是否唯一命中。',
      ]);

      final stored = await probe.database.getQuoteById('note-editing');
      final turn = await probe.ask(
        '帮我把这段润色一下，说得更具体、更有条理，别改我的原意。',
        noteContext: AgentNoteContext(
          noteId: 'note-editing',
          content: original.content,
          documentKind: NoteDocumentKind.plain,
          documentRevision: ProposeNoteEditTool.revisionForQuote(stored!),
        ),
      );

      reportTurn('编辑器润色', turn);
      checkProposals(turn, original: stored);

      if (turn.toolNames.contains('explore_notes')) {
        turn.findings.add(
          'noteContext 已绑定当前笔记，却仍调用 explore_notes 去找——'
          '白烧一轮，说明 system prompt 没把绑定笔记讲清楚。',
        );
      }

      await probe.finish();

      expect(turn.error, isNull, reason: '高频路径不应整轮抛异常');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
