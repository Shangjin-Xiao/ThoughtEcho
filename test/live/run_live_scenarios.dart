import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'agent_probe.dart';

Future<void> main(List<String> args) async {
  print('🚀 启动 Thoughter AI 拟真场景评测脚本...');
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = AgentProbeConfig.load();
  final targetModel = args.isNotEmpty
      ? args[0]
      : (Platform.environment['TE_PROBE_MODEL'] ?? 'gemma4:31b');

  final config = base.withModel(targetModel);
  print('📌 目标模型: ${config.model} | Endpoint: ${config.baseUrl}');

  if (!config.isAvailable) {
    print('❌ 错误: 未配置 API 密钥');
    exit(1);
  }

  final tag = config.model.split(':').first;

  // 1. 种子标签
  const seedTags = [
    (id: 'tag-reading-1', name: '读书'),
    (id: 'tag-reading-2', name: '读书'),
    (id: 'tag-daily', name: '日常随笔'),
    (id: 'tag-tech', name: '技术思考'),
    (id: 'tag-philosophy', name: '斯多葛与哲学'),
    (id: 'tag-product', name: '产品与设计'),
    (id: 'tag-work', name: '工作与效率'),
    (id: 'tag-life', name: '生活杂感'),
  ];

  // 2. 22 篇种子笔记
  List<Quote> seedNotes() {
    final now = DateTime.now();
    String daysAgo(int days) =>
        now.subtract(Duration(days: days)).toIso8601String();

    return [
      // 1. 名家名著摘录
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
        content: '并非我们拥有的时间太少，而是我们虚掷了太多。生命足够长久，如果我们善加利用，它足以完成最伟大的事业。',
        date: daysAgo(20),
        sourceAuthor: '塞涅卡',
        sourceWork: '论生命的短促',
        tagIds: const ['tag-reading-1', 'tag-philosophy'],
        weather: 'clear',
        dayPeriod: 'morning',
        location: '杭州·西湖区',
        temperature: '22°C',
      ),
      Quote(
        id: 'seed-excerpt-jobs',
        content: '保持饥饿，保持愚蠢。不要被教条所束缚，不要让别人的意见淹没了你内心的声音。',
        date: daysAgo(25),
        sourceAuthor: '史蒂夫·乔布斯',
        sourceWork: '斯坦福大学毕业演讲',
        tagIds: const ['tag-reading-2', 'tag-work'],
        weather: 'cloudy',
        dayPeriod: 'afternoon',
        location: '上海·张江高科',
        temperature: '24°C',
        favoriteCount: 1,
      ),
      Quote(
        id: 'seed-excerpt-balzac',
        content: '苦难对于天才是一块垫脚石，对于能干的人是一笔财富，对于弱者是个万丈深渊。',
        date: daysAgo(40),
        sourceAuthor: '奥诺雷·德·巴尔扎克',
        sourceWork: '人间喜剧',
        tagIds: const ['tag-reading-1', 'tag-life'],
        weather: 'rainy',
        dayPeriod: 'morning',
        location: '杭州',
        temperature: '15°C',
      ),
      Quote(
        id: 'seed-excerpt-luxun',
        content: '希望是本无所谓有，无所谓无的。这正如地上的路；其实地上本没有路，走的人多了，也便成了路。',
        date: daysAgo(60),
        sourceAuthor: '鲁迅',
        sourceWork: '故乡',
        tagIds: const ['tag-reading-1'],
        weather: 'cloudy',
        dayPeriod: 'night',
        location: '绍兴',
        temperature: '12°C',
      ),
      Quote(
        id: 'seed-excerpt-aurelius',
        content: '你拥有控制自己思想的力量，而不是外界事件。认识到这一点，你就会找到力量。',
        date: daysAgo(8),
        sourceAuthor: '马可·奥勒留',
        sourceWork: '沉思录',
        tagIds: const ['tag-reading-1', 'tag-philosophy'],
        weather: 'clear',
        dayPeriod: 'dawn',
        location: '杭州·天目里',
        temperature: '19°C',
      ),
      Quote(
        id: 'seed-excerpt-maugham',
        content: '满地都是六便士，他却抬头看见了月亮。',
        date: daysAgo(50),
        sourceAuthor: '威廉·萨默塞特·毛姆',
        sourceWork: '月亮与六便士',
        tagIds: const ['tag-reading-2', 'tag-life'],
        weather: 'clear',
        dayPeriod: 'night',
        location: '杭州',
        temperature: '20°C',
        favoriteCount: 1,
      ),

      // 2. 个人生活与技术日记
      Quote(
        id: 'seed-daily-subway',
        content: '早高峰2号线挤得像沙丁鱼罐头，耳机里放着播客。突然想到状态管理的事件解耦其实跟人流调度一模一样，都是背压问题。',
        date: daysAgo(1),
        tagIds: const ['tag-daily', 'tag-tech'],
        weather: 'cloudy',
        dayPeriod: 'morning',
        location: '杭州·钱江世纪城',
        temperature: '23°C',
      ),
      Quote(
        id: 'seed-daily-flow',
        content: '下午在海创园咖啡馆写完了架构重构提案，三个小时完全进入心流状态。没有无意义的会议和被打断，这种感觉太爽了。',
        date: daysAgo(2),
        tagIds: const ['tag-daily', 'tag-work'],
        weather: 'clear',
        dayPeriod: 'afternoon',
        location: '杭州·海创园',
        temperature: '26°C',
        favoriteCount: 1,
      ),
      Quote(
        id: 'seed-daily-anxiety',
        content:
            '凌晨两点半突然醒来，想起下半年项目的技术路线选型，翻来覆去睡不着。爬起来泡了杯热牛奶，其实焦虑只是因为把未来的不确定性折现到了今天。',
        date: daysAgo(4),
        tagIds: const ['tag-daily', 'tag-life'],
        weather: 'rainy',
        dayPeriod: 'night',
        location: '杭州·西湖区文三路',
        temperature: '19°C',
      ),
      Quote(
        id: 'seed-daily-latte',
        content:
            '楼下新开了一家手冲咖啡店，耶加雪菲的花香很明显。跟老板聊了聊，他也是程序员转行做咖啡的。他说代码会过时，但好喝的咖啡不会。',
        date: daysAgo(5),
        tagIds: const ['tag-daily', 'tag-life'],
        weather: 'clear',
        dayPeriod: 'afternoon',
        location: '杭州·天目里',
        temperature: '25°C',
      ),
      Quote(
        id: 'seed-daily-offline',
        content:
            '思考了很久 Local-First 架构的核心哲学：数据所有权必须回归用户本身。云端只负责同步和多端协作，没有网络时一切功能必须丝滑可用。',
        date: daysAgo(6),
        tagIds: const ['tag-tech', 'tag-product'],
        weather: 'clear',
        dayPeriod: 'evening',
        location: '杭州·海创园',
        temperature: '21°C',
      ),
      Quote(
        id: 'seed-daily-cat',
        content: '小区里那只橘猫今天居然主动蹭我的裤脚，还发出呼噜呼噜的声音。给它喂了半根香肠，治愈了一整天的疲惫。',
        date: daysAgo(7),
        tagIds: const ['tag-daily', 'tag-life'],
        weather: 'cloudy',
        dayPeriod: 'evening',
        location: '杭州·西湖区',
        temperature: '22°C',
      ),
      Quote(
        id: 'seed-daily-hiking',
        content: '周末去九溪十八涧徒步，一路绿意盎然，溪水冰凉。远离电脑屏幕和即时消息，在森林里大口呼吸，整个人像被重置了一遍。',
        date: daysAgo(9),
        tagIds: const ['tag-daily', 'tag-life'],
        weather: 'clear',
        dayPeriod: 'afternoon',
        location: '杭州·九溪',
        temperature: '24°C',
        favoriteCount: 1,
      ),
      Quote(
        id: 'seed-daily-refactor',
        content: '花了一整天把遗留的全局状态重构成单一数据流，删掉了 400 行胶水代码。虽然外部界面看起来没有任何变化，但内心极度舒适。',
        date: daysAgo(10),
        tagIds: const ['tag-tech', 'tag-work'],
        weather: 'cloudy',
        dayPeriod: 'night',
        location: '杭州·海创园',
        temperature: '20°C',
      ),

      // 3. 用户自签名原创笔记（用户在正文或作者栏署名自己的笔名「阿澈」）
      Quote(
        id: 'seed-user-signed-running',
        content: '夜跑西湖十公里，微风拂面，苏堤上游人渐稀。汗水顺着脸颊流下来，所有的杂念都被脚步声踩碎在夜色里。——写于夜跑归来，阿澈',
        date: daysAgo(3),
        sourceAuthor: '阿澈',
        tagIds: const ['tag-daily', 'tag-life'],
        weather: 'clear',
        dayPeriod: 'night',
        location: '杭州·西湖断桥',
        temperature: '21°C',
        favoriteCount: 1,
      ),
      Quote(
        id: 'seed-user-signed-future',
        content: '致五年后的阿澈：希望你依然对构建好产品保持好奇与热情，依然会在深夜为优雅的代码心动，依然敢于做出改变一生的决定。',
        date: daysAgo(12),
        sourceAuthor: '阿澈',
        tagIds: const ['tag-daily', 'tag-philosophy'],
        weather: 'clear',
        dayPeriod: 'night',
        location: '杭州·西湖区',
        temperature: '18°C',
      ),
      Quote(
        id: 'seed-user-signed-garden',
        content: '海创园的晚霞烧红了半边天，坐在长椅上吹着晚风，突然觉得生活除了赶进度，还有这些停顿的片刻值得铭记。——阿澈随笔',
        date: daysAgo(15),
        tagIds: const ['tag-daily', 'tag-life'],
        weather: 'clear',
        dayPeriod: 'evening',
        location: '杭州·海创园',
        temperature: '25°C',
      ),

      // 4. 无作者/未标注出处的摘录
      Quote(
        id: 'seed-unattributed-quote-1',
        content: '真正重要的东西，用眼睛是看不见的，只有用心才能看清楚。',
        date: daysAgo(30),
        tagIds: const ['tag-reading-1'],
        weather: 'cloudy',
        dayPeriod: 'morning',
        location: '杭州',
        temperature: '17°C',
      ),
      Quote(
        id: 'seed-unattributed-quote-2',
        content: '每一个不曾起舞的日子，都是对生命的辜负。',
        date: daysAgo(35),
        tagIds: const ['tag-reading-2', 'tag-philosophy'],
        weather: 'clear',
        dayPeriod: 'afternoon',
        location: '杭州',
        temperature: '22°C',
      ),
      Quote(
        id: 'seed-unattributed-quote-3',
        content: '人的一切痛苦，本质上都是对自己的无能的愤怒。',
        date: daysAgo(45),
        tagIds: const ['tag-reading-1'],
        weather: 'rainy',
        dayPeriod: 'night',
        location: '杭州',
        temperature: '16°C',
      ),
      Quote(
        id: 'seed-daily-debug',
        content:
            '排查了一个诡异的并发竞争 Bug，原来是异步通知在已销毁的实例上触发了微任务。写代码千万不能心存侥幸，边界防御必须扎扎实实。',
        date: daysAgo(11),
        tagIds: const ['tag-tech', 'tag-work'],
        weather: 'clear',
        dayPeriod: 'afternoon',
        location: '杭州·海创园',
        temperature: '23°C',
      ),
    ];
  }

  // =========================================================================
  // 场景 1: 自然闲聊中的孤独归属辨识（未设昵称）
  // =========================================================================
  print(
      '\n═══════════════════════════════════════════════════════════════════');
  print('▶ 开始评测 [场景 1]: 自然闲聊中的孤独归属辨识（未设昵称）');
  print('═══════════════════════════════════════════════════════════════════');

  final probe1 = await AgentProbe.start(
    scenario: '01-自然闲聊孤独归属-$tag',
    config: config,
    nickname: '',
    seedTagsWithIds: seedTags,
    seedNotes: seedNotes(),
  );

  final askSolitude = await probe1.ask(
    '诶，我记得我之前记过一句关于孤独的话，但我好像没经历过那么深刻的孤独吧，你帮我翻翻那是怎么回事？',
  );
  reportTurn('自然口吻询问孤独', askSolitude);

  final reply1 = askSolitude.response?.content ?? '';
  print('\n>>> [场景 1] AI 回复内容:\n$reply1\n');

  final usedExplore1 =
      askSolitude.toolCalls.any((c) => c['tool'] == 'explore_notes');
  print('🔍 工具调用 explore_notes: ${usedExplore1 ? "✅ 命中" : "❌ 未调用"}');

  final mentionsTurkle = reply1.contains('雪莉·特克尔') || reply1.contains('特克尔');
  final mentionsWork = reply1.contains('群体性孤独');
  final clarifiesExcerpt = reply1.contains('摘录') ||
      reply1.contains('他人') ||
      reply1.contains('引用') ||
      reply1.contains('不是你自己写') ||
      reply1.contains('书中');

  print('💡 识别出作者（雪莉·特克尔）: ${mentionsTurkle ? "✅" : "❌"}');
  print('💡 识别出作品名（群体性孤独）: ${mentionsWork ? "✅" : "❌"}');
  print('💡 主动澄清这是摘录/他人观点而非用户自己写的: ${clarifiesExcerpt ? "✅" : "❌"}');

  final transcript1 = await probe1.finish();
  print('📁 场景 1 报告已生成: ${transcript1.path}');

  // =========================================================================
  // 场景 2: 未设昵称时对「自签名原创」阿澈的归属辨析
  // =========================================================================
  print(
      '\n═══════════════════════════════════════════════════════════════════');
  print('▶ 开始评测 [场景 2]: 未设昵称时对「自签名原创」阿澈的归属辨析');
  print('═══════════════════════════════════════════════════════════════════');

  final probe2 = await AgentProbe.start(
    scenario: '02-自签名阿澈辨析-$tag',
    config: config,
    nickname: '',
    seedTagsWithIds: seedTags,
    seedNotes: seedNotes(),
  );

  final askChe = await probe2.ask(
    '我之前有没有在断桥或者海创园留下过什么感慨？那个署名阿澈的是怎么回事？',
  );
  reportTurn('询问阿澈署名笔记', askChe);

  final reply2 = askChe.response?.content ?? '';
  print('\n>>> [场景 2] AI 回复内容:\n$reply2\n');

  final treatsAsOriginal = reply2.contains('你自己') ||
      reply2.contains('你的笔名') ||
      reply2.contains('你的随笔') ||
      reply2.contains('你的原创') ||
      reply2.contains('夜跑') ||
      reply2.contains('海创园');

  print('💡 识别为用户原创/生活随笔/笔名: ${treatsAsOriginal ? "✅" : "❌"}');

  final transcript2 = await probe2.finish();
  print('📁 场景 2 报告已生成: ${transcript2.path}');

  // =========================================================================
  // 场景 3: 个人周总结（严禁将名家名句算在用户头上）
  // =========================================================================
  print(
      '\n═══════════════════════════════════════════════════════════════════');
  print('▶ 开始评测 [场景 3]: 个人周总结（过滤名家摘录）');
  print('═══════════════════════════════════════════════════════════════════');

  final probe3 = await AgentProbe.start(
    scenario: '03-个人周总结过滤摘录-$tag',
    config: config,
    nickname: '',
    seedTagsWithIds: seedTags,
    seedNotes: seedNotes(),
  );

  final askSummary = await probe3.ask(
    '帮我回顾一下最近两周我自己真实的生活和技术思考，总结一下我最近的状态。注意我只要我自己经历的，那些名人名言就别算我头上了。',
  );
  reportTurn('生成个人周总结', askSummary);

  final reply3 = askSummary.response?.content ?? '';
  print('\n>>> [场景 3] AI 回复内容:\n$reply3\n');

  final includesUserLife = reply3.contains('心流') ||
      reply3.contains('Local-First') ||
      reply3.contains('橘猫') ||
      reply3.contains('夜跑') ||
      reply3.contains('海创园') ||
      reply3.contains('九溪');
  final excludesFamousQuotesAsMine = !reply3.contains('你写了《沉思录》') &&
      !reply3.contains('你的名言“保持饥饿”') &&
      !reply3.contains('你在《月亮与六便士》中提到');

  print('💡 包含用户真实生活/技术内容: ${includesUserLife ? "✅" : "❌"}');
  print('💡 正确排除名家名言侵入个人经历: ${excludesFamousQuotesAsMine ? "✅" : "❌"}');

  final transcript3 = await probe3.finish();
  print('📁 场景 3 报告已生成: ${transcript3.path}');

  // =========================================================================
  // 场景 4: 自然口语偏好纠正与长期记忆写入
  // =========================================================================
  print(
      '\n═══════════════════════════════════════════════════════════════════');
  print('▶ 开始评测 [场景 4]: 自然口语偏好纠正与长期记忆写入');
  print('═══════════════════════════════════════════════════════════════════');

  final probe4 = await AgentProbe.start(
    scenario: '04-口语偏好纠正记忆-$tag',
    config: config,
    nickname: '小陈',
    seedTagsWithIds: seedTags,
    seedNotes: seedNotes(),
  );

  final askCorrection = await probe4.ask(
    '以后别叫我小陈了，叫我阿澈就好。还有，我平时写代码主要用 Dart 和 Rust，以后给技术建议优先从这两门语言的角度出发。',
  );
  reportTurn('提出偏好纠正', askCorrection);

  final reply4 = askCorrection.response?.content ?? '';
  print('\n>>> [场景 4] AI 回复内容:\n$reply4\n');

  await reportMemory(probe4, '纠正后的记忆库状态');

  final profile4 = await probe4.memory.activeProfile();
  final nicknameUpdated = probe4.settings.userNickname == '阿澈' ||
      profile4.any((p) => p.directive.contains('阿澈'));
  print('💡 称呼成功更新为「阿澈」: ${nicknameUpdated ? "✅" : "❌"}');

  final transcript4 = await probe4.finish();
  print('📁 场景 4 报告已生成: ${transcript4.path}');

  // =========================================================================
  // 场景 5: 偏好翻转与原位覆盖（Supersede）
  // =========================================================================
  print(
      '\n═══════════════════════════════════════════════════════════════════');
  print('▶ 开始评测 [场景 5]: 偏好翻转与原位覆盖（Supersede）');
  print('═══════════════════════════════════════════════════════════════════');

  final probe5 = await AgentProbe.start(
    scenario: '05-偏好翻转原位覆盖-$tag',
    config: config,
    nickname: '阿澈',
    seedTagsWithIds: seedTags,
    seedNotes: seedNotes(),
  );

  await probe5.ask('我特别喜欢喝手冲咖啡，每天至少两杯。');
  await reportMemory(probe5, '第一次记录咖啡偏好');

  await probe5.ask('最近医生建议我戒咖啡因，我现在完全不喝咖啡了，改喝普洱茶了。');
  await reportMemory(probe5, '翻转咖啡偏好为茶');

  final facts5 = await probe5.memory.searchFacts('咖啡');
  final activeCoffeeFacts =
      facts5.where((f) => f.fact.supersededBy == null).toList();
  print('💡 当前活跃的咖啡相关事实数: ${activeCoffeeFacts.length} (期望 0 或 1 条戒咖啡声明)');

  final transcript5 = await probe5.finish();
  print('📁 场景 5 报告已生成: ${transcript5.path}');

  print(
      '\n═══════════════════════════════════════════════════════════════════');
  print('🎉 全部拟真评测场景执行完毕！');
  print('═══════════════════════════════════════════════════════════════════');
  exit(0);
}
