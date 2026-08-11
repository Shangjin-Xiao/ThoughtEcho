// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';

import 'agent_probe.dart';

/// 第四批：长期记忆与「他写的 / 他摘的」归属判断。
///
/// 这两件事在别的批次里看不到：高频场景没开记忆工具，也没有播种带 author/source
/// 的摘录，所以模型把摘录当成用户自述、或者把笔记内容抄进记忆这类问题不会暴露。
///
/// 仍然是探针：模型行为只记录不断言。唯一的硬断言是「整轮不许抛异常」，
/// 以及记忆库里不许出现明显越界的内容（那是我们自己的边界，不是模型的随机性）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = AgentProbeConfig.load();
  final config = base.withModel(
    Platform.environment['TE_PROBE_MODEL'] ?? AgentProbeConfig.recommendedModel,
  );
  final tag = config.model.split(':').first;

  const seedTags = [
    (id: 'tag-reading', name: '读书'),
    (id: 'tag-daily', name: '日常'),
  ];

  /// 一半摘录一半原创，且刻意让"孤独"只出现在摘录里：
  /// 问「我写过孤独吗」时，正确答案是"你摘过，但没自己写过"。
  List<Quote> seedNotes() {
    final now = DateTime.now();
    String daysAgo(int days) =>
        now.subtract(Duration(days: days)).toIso8601String();

    return [
      // —— 摘录：他人作品 ——
      Quote(
        id: 'seed-excerpt-solitude',
        content: '我们从未如此孤独，也从未如此不愿独处。',
        date: daysAgo(9),
        sourceAuthor: '雪莉·特克尔',
        sourceWork: '群体性孤独',
        tagIds: const ['tag-reading'],
      ),
      Quote(
        id: 'seed-excerpt-slow',
        content: '慢下来不是效率的敌人，而是深度的前提。',
        date: daysAgo(6),
        sourceAuthor: '卡尔·奥诺雷',
        sourceWork: '慢活',
        tagIds: const ['tag-reading'],
      ),
      // —— 原创：用户自己写的，没有 author/source ——
      Quote(
        id: 'seed-own-commute',
        content: '早高峰地铁上又在想那个接口该怎么拆。到公司反而什么都记不起来了，'
            '大概是被人群挤散了。',
        date: daysAgo(4),
        tagIds: const ['tag-daily'],
      ),
      Quote(
        id: 'seed-own-focus',
        content: '这周三次都是下午三点后才进入状态。也许我根本不适合早上写代码，'
            '别再跟自己较劲了。',
        date: daysAgo(2),
        tagIds: const ['tag-daily'],
      ),
      // —— 原创但签了自己的名：author 不等于「这是摘录」——
      Quote(
        id: 'seed-own-signed',
        content: '写下来的那一刻，事情才算真的发生过。',
        date: daysAgo(1),
        sourceAuthor: '阿澈',
        tagIds: const ['tag-daily'],
      ),
    ];
  }

  group('Agent 记忆与归属（真实 API）', () {
    if (!config.isAvailable) {
      test('skipped - 未配置凭据', () {
        print('⚠️  未找到 API 密钥，跳过真实 API 探针。');
        print('   凭据文件：${AgentProbeConfig.credentialsPath}');
        print('   或设置 TE_TEST_API_KEY 环境变量。');
      });
      return;
    }

    // -- 场景 1：纠正 → 跨会话仍然生效 ------------------------------------
    test('跨会话记忆：这一轮被纠正，下一个会话还记得', () async {
      final probe = await AgentProbe.start(
        scenario: '04-跨会话记忆-$tag',
        config: config,
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );
      probe.transcript.notes.addAll([
        '第 1 轮用户明确纠正表达偏好，期望它调 remember 写进画像层。',
        '第 2 轮 carryHistory=false 模拟重开会话：历史清空，只剩画像块自动注入。'
            '看它是否遵守偏好，以及是否会重复问一遍同样的事。',
      ]);

      final correction = await probe.ask(
        '你回我的话太长了，以后短一点，用碎句，别一条条列。记住这个。',
      );
      reportTurn('纠正', correction);
      await reportMemory(probe, '第 1 轮之后');

      final freshSession = await probe.ask(
        '我最近在琢磨什么？',
        carryHistory: false,
      );
      reportTurn('重开会话', freshSession);
      await reportMemory(probe, '第 2 轮之后');

      if (!correction.toolNames.contains('remember')) {
        correction.findings.add('用户说了"记住这个"，但它没调 remember。');
      }
      // 记忆与 explore_notes 的边界：笔记里写过的内容不该被抄进记忆，
      // 否则同一件事会有两套互相打架的检索。
      await _flagNoteContentLeakedIntoMemory(probe, freshSession);
      final replyLength = freshSession.response?.content.length ?? 0;
      probe.transcript.notes.add(
        '重开会话后的回复 $replyLength 字（碎句偏好是否生效需人工读）。',
      );

      await probe.finish();
      expect(correction.error, isNull);
      expect(freshSession.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));

    // -- 场景 2：摘录不是自述 ---------------------------------------------
    test('归属判断：只有摘录命中时，不能说成"你写过"', () async {
      final probe = await AgentProbe.start(
        scenario: '05-摘录与原创-$tag',
        config: config,
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );
      probe.transcript.notes.addAll([
        '库里"孤独"只出现在一条带 author/source 的摘录里，用户自己没写过。',
        '期望：说清那是摘自《群体性孤独》，而不是"你写过孤独"。',
        '另一条 seed-own-signed 署名"阿澈"（用户本人），期望不被当成摘录。',
      ]);

      final askSolitude = await probe.ask('我自己写过关于孤独的东西吗？');
      reportTurn('孤独', askSolitude);
      _flagAttribution(
        askSolitude,
        mustMention: const ['群体性孤独', '特克尔', '摘'],
        label: '孤独',
      );

      final askSelf = await probe.ask('那根据我自己写的笔记，最近我在跟什么较劲？');
      reportTurn('自我分析', askSelf);
      final analysis = askSelf.response?.content ?? '';
      if (analysis.contains('慢活') || analysis.contains('奥诺雷')) {
        askSelf.findings.add('把摘录当成了用户自己的想法（提到了《慢活》/奥诺雷）。');
      }

      await probe.finish();
      expect(askSolitude.error, isNull);
      expect(askSelf.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));

    // -- 场景 3：偏好改了要改同一条，不能追加一条相反的 --------------------
    test('偏好翻转：改同一条，而不是并存两条互相矛盾的画像', () async {
      final probe = await AgentProbe.start(
        scenario: '07-偏好翻转-$tag',
        config: config,
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );
      probe.transcript.notes.addAll([
        '先记下"回复要短"，再让用户反过来要求"展开写长一点"。',
        '画像块只带指令不带 id，模型要改就得先 recall 拿 id。这一步是弱模型最容易'
            '跳过的：跳过就会 add 一条相反的，两条并存后它只能随机挑一条遵守。',
      ]);

      final first = await probe.ask('以后回我短一点，用碎句。记住。');
      reportTurn('第一次偏好', first);
      await reportMemory(probe, '第一次偏好之后');

      final flipped = await probe.ask(
        '我改主意了，以后请展开写，把理由讲清楚，别再用碎句了。记住。',
        carryHistory: false,
      );
      reportTurn('偏好翻转', flipped);
      await reportMemory(probe, '偏好翻转之后');

      final profile = await probe.memory.activeProfile();
      final short = profile.where((e) => e.directive.contains('碎句')).length;
      if (profile.length > 1 && short > 0) {
        flipped.findings.add(
          '偏好翻转后画像里还留着 $short 条"碎句"指令，共 ${profile.length} 条：'
          '两条互相矛盾的表达偏好会让它随机挑一条遵守。'
          '看它这一轮是 update 了同一条，还是又 add 了一条。',
        );
      }
      probe.transcript.notes.add('翻转那轮调用的工具：${flipped.toolNames}');

      await probe.finish();
      expect(first.error, isNull);
      expect(flipped.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));

    // -- 场景 4：用户填写的称呼 -------------------------------------------
    test('称呼：设置里填了就直接用，不再问一遍', () async {
      final probe = await AgentProbe.start(
        scenario: '06-用户称呼-$tag',
        config: config,
        nickname: '阿澈',
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );
      probe.transcript.notes.add(
        '设置里已填称呼「阿澈」，画像块应带 [身份·用户填写] 一行。',
      );

      final greeting = await probe.ask('嗨，随便聊聊吧。');
      reportTurn('打招呼', greeting);

      final reply = greeting.response?.content ?? '';
      if (!reply.contains('阿澈')) {
        greeting.findings.add('画像里有称呼，回复却没用上。');
      }
      if (reply.contains('怎么称呼') || reply.contains('如何称呼')) {
        greeting.findings.add('已经知道称呼了还在问用户怎么称呼。');
      }

      await probe.finish();
      expect(greeting.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 6)));
  });
}

/// 记忆边界的粗筛：笔记正文里的特征词不该出现在记忆库里。
Future<void> _flagNoteContentLeakedIntoMemory(
  AgentProbe probe,
  ProbeTurn turn,
) async {
  const noteOnlyPhrases = ['地铁', '接口', '下午三点', '群体性孤独', '慢活'];
  final profile = await probe.memory.activeProfile();
  final facts = await probe.memory.searchFacts('', limit: 20);
  final stored = [
    for (final entry in profile) entry.directive,
    for (final hit in facts) hit.fact.content,
  ];
  for (final text in stored) {
    final leaked = noteOnlyPhrases.where(text.contains).toList(growable: false);
    if (leaked.isNotEmpty) {
      turn.findings.add(
        '记忆里出现了只在笔记正文里有的内容（${leaked.join('、')}）：'
        '「$text」。这属于 explore_notes 的职责，不该进记忆。',
      );
    }
  }
}

/// 归属类回答的粗筛：命中任意一个关键词就算提到了出处。
void _flagAttribution(
  ProbeTurn turn, {
  required List<String> mustMention,
  required String label,
}) {
  final content = turn.response?.content ?? '';
  if (content.isEmpty) return;
  final mentioned = mustMention.any(content.contains);
  if (!mentioned) {
    turn.findings.add(
      '$label：回复里没有任何出处线索（${mustMention.join('/')}），'
      '需人工确认它是不是把摘录说成了用户自己写的。',
    );
  }
}
