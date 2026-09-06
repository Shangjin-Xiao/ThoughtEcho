// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';

import 'agent_probe.dart';

/// 真实用户场景：长期记忆、偏好交互与「自述 vs 摘录」归属判断。
///
/// 特性：
/// 1. 100% 真实自然口语交互，拒绝考试式问答；
/// 2. 初始状态不预设用户名（nickname: ''），观察模型如何通过语境自主辨析；
/// 3. 22 篇高保真合成笔记：覆盖名家名著、自签名原创随笔、纯个人日常、未署名书摘；
/// 4. 严密监控 Agent 的工具调用、参数合法性与记忆库边界。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = AgentProbeConfig.load();
  final config = base.withModel(
    Platform.environment['TE_PROBE_MODEL'] ?? AgentProbeConfig.recommendedModel,
  );
  final tag = config.model.split(':').first;

  /// 8 个多维度标签体系（包含同名标签重载测试）
  const seedTags = [
    (id: 'tag-reading-1', name: '读书'),
    (id: 'tag-reading-2', name: '读书'), // 故意同名，模拟多端合并
    (id: 'tag-daily', name: '日常随笔'),
    (id: 'tag-tech', name: '技术思考'),
    (id: 'tag-philosophy', name: '斯多葛与哲学'),
    (id: 'tag-product', name: '产品与设计'),
    (id: 'tag-work', name: '工作与效率'),
    (id: 'tag-life', name: '生活杂感'),
  ];

  /// 22 篇高保真拟真笔记（零隐私数据）：
  List<Quote> seedNotes() {
    final now = DateTime.now();
    String daysAgo(int days) =>
        now.subtract(Duration(days: days)).toIso8601String();

    return [
      // -----------------------------------------------------------------------
      // 1. 名家名著摘录（有明确的 sourceAuthor 和 sourceWork）
      // -----------------------------------------------------------------------
      Quote(
        id: 'seed-excerpt-turkle',
        content: '沉浸在连接中却感到孤立，技术承诺免除脆弱的陪伴。我们期待技术能替代真实的人际投入，却忘记了独处才是反思的起点。',
        date: daysAgo(14),
        sourceAuthor: '雪莉·特克尔',
        sourceWork: '群体性孤独',
        tagIds: const ['tag-reading-1', 'tag-tech'],
        weather: 'rainy',
        dayPeriod: 'evening',
        location: '杭州·西湖区',
        temperature: '18°C',
        favoriteCount: 1,
      ),
      Quote(
        id: 'seed-excerpt-seneca',
        content: '我们不是拥有太少的时间，而是荒废了太多。生命足够长，只要我们将它善加利用，它足以让我们完成最伟大的事业。',
        date: daysAgo(12),
        sourceAuthor: '塞内加',
        sourceWork: '论生命之短暂',
        tagIds: const ['tag-reading-2', 'tag-philosophy'],
        weather: 'clear',
        dayPeriod: 'morning',
        location: '杭州·文三路',
        temperature: '20°C',
        favoriteCount: 2,
      ),
      Quote(
        id: 'seed-excerpt-jobs',
        content: '专注不是对你想做的事情说“是”，而是对其他一百个好想法说“不”。你必须仔细挑选，才能做出真正伟大的产品。',
        date: daysAgo(10),
        sourceAuthor: '史蒂夫·乔布斯',
        sourceWork: 'WWDC 演讲',
        tagIds: const ['tag-reading-1', 'tag-product', 'tag-tech'],
        weather: 'cloudy',
        dayPeriod: 'afternoon',
        location: '杭州·西湖区',
        temperature: '24°C',
      ),
      Quote(
        id: 'seed-excerpt-honore',
        content: '慢活并不是散漫或者偷懒，而是在快节奏的世界中，学会在正确的时间以正确的速度做事，掌控自己的生活节奏。',
        date: daysAgo(9),
        sourceAuthor: '卡尔·奥诺雷',
        sourceWork: '慢活',
        tagIds: const ['tag-reading-1', 'tag-philosophy'],
        weather: 'clear',
        dayPeriod: 'morning',
        location: '杭州·西湖区',
        temperature: '22°C',
      ),
      Quote(
        id: 'seed-excerpt-luxun',
        content: '希望是本无所谓有，无所谓无的。这正如地上的路；其实地上本没有路，走的人多了，也便成了路。',
        date: daysAgo(8),
        sourceAuthor: '鲁迅',
        sourceWork: '故乡',
        tagIds: const ['tag-reading-1', 'tag-daily'],
        weather: 'clear',
        dayPeriod: 'dusk',
        location: '绍兴',
        temperature: '19°C',
      ),
      Quote(
        id: 'seed-excerpt-aurelius',
        content: '你有能力控制自己的思想，而不是外部事件。意识到这一点，你就会找到力量。',
        date: daysAgo(7),
        sourceAuthor: '马可·奥勒留',
        sourceWork: '沉思录',
        tagIds: const ['tag-reading-2', 'tag-philosophy'],
        weather: 'clear',
        dayPeriod: 'dawn',
        location: '杭州',
        temperature: '15°C',
      ),
      Quote(
        id: 'seed-excerpt-maugham',
        content: '满地都是六便士，他却抬头看见了月亮。',
        date: daysAgo(6),
        sourceAuthor: '毛姆',
        sourceWork: '月亮与六便士',
        tagIds: const ['tag-reading-1'],
        weather: 'rainy',
        dayPeriod: 'midnight',
        location: '杭州',
        temperature: '17°C',
      ),

      // -----------------------------------------------------------------------
      // 2. 用户无作者原创日记与日常思考（无 author/sourceWork，纯个人自述语境）
      // -----------------------------------------------------------------------
      Quote(
        id: 'seed-own-commute',
        content:
            '早高峰地铁2号线又挤爆了。路上在想微内核架构与单体解耦的事情，警惕过早引入分布式服务，往往清晰的模块边界才是最稳健的。到公司被拉去开晨会，差点把这点想法搞忘了。',
        date: daysAgo(6),
        tagIds: const ['tag-tech', 'tag-daily'],
        weather: 'fog',
        dayPeriod: 'dawn',
        location: '杭州·地铁2号线',
        temperature: '16°C',
      ),
      Quote(
        id: 'seed-own-focus',
        content:
            '连续三天都是下午三点后才能完全进入心流状态。早上的碎片化会议严重破坏了深度思考，打算下周把所有的沟通集中在上午，把下午的黄金时间留给编码。',
        date: daysAgo(5),
        tagIds: const ['tag-work', 'tag-daily'],
        weather: 'clear',
        dayPeriod: 'afternoon',
        location: '杭州·阿里中心',
        temperature: '25°C',
      ),
      Quote(
        id: 'seed-own-time-anxiety',
        content:
            '读完塞内加的随笔后深夜失眠。总觉得有很多书没读、很多技术方案没写，这种对时间流逝的焦虑本质上是对失控的恐惧。学会接纳当下，哪怕今天只专注做好了一件事。',
        date: daysAgo(4),
        tagIds: const ['tag-philosophy', 'tag-daily'],
        weather: 'rainy',
        dayPeriod: 'midnight',
        location: '杭州·西湖区',
        temperature: '17°C',
      ),
      Quote(
        id: 'seed-own-product-craft',
        content:
            '清晨在咖啡馆喝燕麦拿铁，阳光透进窗户。突然意识到 Local-First 应用最难的不是数据存储，而是多端冲突时的确定性反馈，必须让用户完全信任数据绝不会丢失。',
        date: daysAgo(3),
        tagIds: const ['tag-product', 'tag-tech'],
        weather: 'clear',
        dayPeriod: 'morning',
        location: '杭州·咖啡馆',
        temperature: '21°C',
      ),
      Quote(
        id: 'seed-own-cat',
        content:
            '下班路上在小区楼下遇到一只不怕人的大橘猫，蹲下来喂了它一根猫条。它蹭我裤腿的时候，感觉一整天的疲惫瞬间被治愈了。生活中微小的善意真好。',
        date: daysAgo(2),
        tagIds: const ['tag-life', 'tag-daily'],
        weather: 'clear',
        dayPeriod: 'evening',
        location: '杭州·小区花园',
        temperature: '22°C',
      ),
      Quote(
        id: 'seed-own-hiking',
        content: '周六去龙井九溪爬山徒步，山里空气极度清新。路上没有信号，反而让人真正放空了大脑。现代人太需要这种定期的数字排毒了。',
        date: daysAgo(1),
        tagIds: const ['tag-life', 'tag-daily'],
        weather: 'sunny',
        dayPeriod: 'afternoon',
        location: '杭州·九溪烟树',
        temperature: '26°C',
      ),
      Quote(
        id: 'seed-own-ui-refactor',
        content:
            '把项目的调色板重构了一遍，彻底移除了那些写死的 Tailwind 颜色代码，全部接入 M3 语义色和设计令牌。代码整洁度大幅提升，视觉一致性感觉舒服多了。',
        date: daysAgo(1),
        tagIds: const ['tag-tech'],
        weather: 'sunny',
        dayPeriod: 'afternoon',
        location: '杭州·书房',
        temperature: '25°C',
      ),

      // -----------------------------------------------------------------------
      // 3. 用户自签名原创随笔（虽有 sourceAuthor: '阿澈'，但语境为第一人称手记，无外部书名）
      // -----------------------------------------------------------------------
      Quote(
        id: 'seed-signed-writing',
        content: '写下来的那一刻，混乱的念头才被赋予了骨骼。文字是时间的锚点，不需要写给别人看，诚实地记录真实的自己就足够了。——阿澈',
        date: daysAgo(3),
        sourceAuthor: '阿澈',
        tagIds: const ['tag-daily', 'tag-philosophy'],
        weather: 'drizzle',
        dayPeriod: 'dusk',
        location: '杭州·西湖区',
        temperature: '19°C',
      ),
      Quote(
        id: 'seed-signed-tech-creed',
        content:
            '不要为了炫技而引入复杂的分布式状态机。最稳妥的客户端架构往往是无状态的单向数据流与确定性的本地日志。写给未来的自己：别在简单问题上搞复杂设计。',
        date: daysAgo(2),
        sourceAuthor: '阿澈',
        sourceWork: '阿澈的代码手记',
        tagIds: const ['tag-tech', 'tag-work'],
        weather: 'sunny',
        dayPeriod: 'afternoon',
        location: '杭州·海创园',
        temperature: '26°C',
      ),
      Quote(
        id: 'seed-signed-running',
        content: '夜跑西湖5公里，配速5分20秒。大汗淋漓之后，白天在单体解耦上卡壳的问题突然有了灵感。身体动起来，大脑才会通透。——阿澈',
        date: daysAgo(1),
        sourceAuthor: '阿澈',
        tagIds: const ['tag-life', 'tag-daily'],
        weather: 'clear',
        dayPeriod: 'night',
        location: '杭州·断桥',
        temperature: '21°C',
      ),

      // -----------------------------------------------------------------------
      // 4. 缺失作者出处但带“读书”标签的经典引文（测试无作者元数据时的常识与标签理解）
      // -----------------------------------------------------------------------
      Quote(
        id: 'seed-unattributed-socrates',
        content: '未经审视的人生是不值得过的。',
        date: daysAgo(11),
        tagIds: const ['tag-reading-1', 'tag-philosophy'],
      ),
      Quote(
        id: 'seed-unattributed-dostoevsky',
        content: '我只担心一件事，我怕我配不上我所受的苦难。',
        date: daysAgo(9),
        tagIds: const ['tag-reading-2', 'tag-philosophy'],
      ),
      Quote(
        id: 'seed-unattributed-hemingway',
        content: '生活总是让我们遍体鳞伤，但到后来，那些受伤的地方一定会变成我们最强壮的地方。',
        date: daysAgo(5),
        tagIds: const ['tag-reading-1'],
      ),
    ];
  }

  group('Thoughter AI 拟真场景综合评测', () {
    if (!config.isAvailable) {
      test('skipped - 未配置凭据', () {
        print('⚠️  未找到 API 密钥，跳过真实 API 探针。');
      });
      return;
    }

    // =========================================================================
    // 场景 1：自然闲聊与“孤独”归属辨识（未设昵称）
    // =========================================================================
    test('场景 1: 自然闲聊中的孤独归属辨识（未设昵称）', () async {
      final probe = await AgentProbe.start(
        scenario: '01-自然闲聊孤独归属-$tag',
        config: config,
        nickname: '', // 刻意不填昵称，观察模型纯语义理解
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );
      probe.transcript.notes.addAll([
        '前置条件：未设置昵称（nickname: ' '）。',
        '真实用户口吻发起询问，测试模型是否能查出雪莉·特克尔《群体性孤独》，并分清这不是用户的经历。',
      ]);

      final askSolitude = await probe.ask(
        '诶，我记得我之前记过一句关于孤独的话，但我好像没经历过那么深刻的孤独吧，你帮我翻翻那是怎么回事？',
      );
      reportTurn('自然口吻询问孤独', askSolitude);

      final reply = askSolitude.response?.content ?? '';
      print('\n>>> [场景 1] AI 回复内容:\n$reply\n');

      _flagAttribution(
        askSolitude,
        mustMention: const ['群体性孤独', '特克尔', '摘'],
        label: '孤独',
      );

      await probe.finish();
      expect(askSolitude.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));

    // =========================================================================
    // 场景 2：自签名随笔深度语义推理（阿澈是别人还是我自己？）
    // =========================================================================
    test('场景 2: 署名随笔深度语义推理（未设昵称）', () async {
      final probe = await AgentProbe.start(
        scenario: '02-自签名随笔推理-$tag',
        config: config,
        nickname: '', // 未设昵称
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );
      probe.transcript.notes.addAll([
        '前置条件：未设置昵称。',
        '用户口语提问：笔记里提到架构和夜跑的署名“阿澈”，究竟是别人还是用户自己？',
        '测试点：模型是否能根据第一人称写日记口吻（夜跑、晨会、写给未来的自己）推断出阿澈是用户自己。',
      ]);

      final askSigned = await probe.ask(
        '我总感觉我以前记过一段关于不要搞复杂分布式架构的话，那个署名写着阿澈的是谁来着？是哪个名家还是我自己啊？',
      );
      reportTurn('自签名身份辨析', askSigned);

      final reply = askSigned.response?.content ?? '';
      print('\n>>> [场景 2] AI 回复内容:\n$reply\n');

      await probe.finish();
      expect(askSigned.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));

    // =========================================================================
    // 场景 3：个人周总结梳理（过滤名家名篇，提取真实个人心迹）
    // =========================================================================
    test('场景 3: 个人周总结（精准过滤名家摘录，聚焦个人真实日记）', () async {
      final probe = await AgentProbe.start(
        scenario: '03-个人周总结提取-$tag',
        config: config,
        nickname: '',
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );
      probe.transcript.notes.addAll([
        '前置条件：未设置昵称。',
        '用户要求：梳理生活和技术思考，明确要求过滤名家书摘。',
        '测试点：输出应包含地铁解耦、心流、深夜失眠、九溪爬山、橘猫等，绝不能把塞内加、特克尔、乔布斯列为用户经历。',
      ]);

      final askSummary = await probe.ask(
        '最近想写个个人周总结，你帮我梳理一下我最近真实记录的生活和技术思考呗，把那些名家名著名言先撇开哈。',
      );
      reportTurn('个人心迹周总结', askSummary);

      final reply = askSummary.response?.content ?? '';
      print('\n>>> [场景 3] AI 回复内容:\n$reply\n');

      await probe.finish();
      expect(askSummary.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));

    // =========================================================================
    // 场景 4：口语化偏好纠正与长效记忆留存
    // =========================================================================
    test('场景 4: 自然偏好纠正与跨会话记忆生效', () async {
      final probe = await AgentProbe.start(
        scenario: '04-口语偏好纠正与跨会话-$tag',
        config: config,
        nickname: '',
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );
      probe.transcript.notes.addAll([
        '第 1 轮：用户自然吐槽“太长了，以后简短点”，并告知“以后叫我阿澈”。',
        '第 2 轮：新会话开启，验证称呼和简短风格是否生效。',
      ]);

      final turn1 = await probe.ask(
        '你每次回答都太长太客套了，看着很累。以后跟我聊天直接说重点，简短点。对了，以后叫我阿澈就好。',
      );
      reportTurn('偏好纠正与称呼告知', turn1);
      await reportMemory(probe, '记录偏好之后');

      // 开启新会话（清空上下文历史，仅依赖长效记忆库）
      final turn2 = await probe.ask(
        '嗨，我今天下午打算开始重构那段遗留代码，有什么一句话的建议吗？',
        carryHistory: false,
      );
      reportTurn('新会话记忆生效检验', turn2);

      final reply2 = turn2.response?.content ?? '';
      print('\n>>> [场景 4 - 新会话] AI 回复内容:\n$reply2\n');

      // 检查记忆库
      await _flagNoteContentLeakedIntoMemory(probe, turn1);

      await probe.finish();
      expect(turn1.error, isNull);
      expect(turn2.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));

    // =========================================================================
    // 场景 5：偏好翻转（从简短变详细）与原位更新
    // =========================================================================
    test('场景 5: 偏好翻转原位更新（避免矛盾条目并存）', () async {
      final probe = await AgentProbe.start(
        scenario: '05-偏好翻转原位更新-$tag',
        config: config,
        nickname: '阿澈',
        seedTagsWithIds: seedTags,
        seedNotes: seedNotes(),
      );

      final turn1 = await probe.ask('以后跟我说话一律极简，只说要点，别废话。记住。');
      reportTurn('初次设定简短偏好', turn1);
      await reportMemory(probe, '第一次偏好');

      final turn2 = await probe.ask(
        '我改主意了，以后请展开详细讲，把背后的原理和原因讲透，分点列出，不要再用极简风格了。记住。',
        carryHistory: false,
      );
      reportTurn('偏好翻转为详细', turn2);
      await reportMemory(probe, '偏好翻转之后');

      final profile = await probe.memory.activeProfile();
      final shortDirectives = profile
          .where(
              (e) => e.directive.contains('极简') || e.directive.contains('简短'))
          .length;
      if (profile.length > 1 && shortDirectives > 0) {
        turn2.findings.add('偏好翻转后画像中依然残留旧的简短偏好，未完成原位 supersede。');
      }

      await probe.finish();
      expect(turn1.error, isNull);
      expect(turn2.error, isNull);
    }, timeout: const Timeout(Duration(minutes: 8)));
  });
}

// ---------------------------------------------------------------------------
// 辅助检查与记录
// ---------------------------------------------------------------------------

void _flagAttribution(
  ProbeTurn turn, {
  required List<String> mustMention,
  required String label,
}) {
  final reply = turn.response?.content ?? '';
  for (final word in mustMention) {
    if (!reply.contains(word)) {
      turn.findings.add(
        '[$label 归属] 回复中缺少关键归属词「$word」：未能明确指出这是摘录而非用户自述。',
      );
    }
  }
}

Future<void> _flagNoteContentLeakedIntoMemory(
  AgentProbe probe,
  ProbeTurn turn,
) async {
  const noteOnlyPhrases = [
    '地铁2号线',
    '微内核',
    '单体解耦',
    '燕麦拿铁',
    '大橘猫',
    '九溪',
    '阿里中心',
    '群体性孤独',
    '塞内加',
  ];
  final profile = await probe.memory.activeProfile();
  final facts = await probe.memory.searchFacts('', limit: 50);
  final stored = [
    for (final entry in profile) entry.directive,
    for (final hit in facts) hit.fact.content,
  ].join('\n');

  for (final phrase in noteOnlyPhrases) {
    if (stored.contains(phrase)) {
      turn.findings.add(
        '⚠️ 记忆边界越界：笔记正文中的具象词「$phrase」被直接写入了 agent_memory.db。',
      );
    }
  }
}
