import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:flutter/foundation.dart';

import '../../live/agent_probe.dart';

class _MockSettingsService extends ChangeNotifier implements SettingsService {
  _MockSettingsService();

  bool memoryEnabled = true;
  String nickname = '阿澈';

  @override
  bool get agentMemoryEnabled => memoryEnabled;

  @override
  String get userNickname => nickname;

  @override
  String? get localeCode => 'zh';

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [
          AIProviderSettings(
            id: 'mock-provider',
            name: 'Mock',
            apiKey: 'mock-key',
            apiUrl: 'https://example.com',
            model: 'mock-model',
          )
        ],
        currentProviderId: 'mock-provider',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<Quote> getSeedNotes() {
  final now = DateTime.now();
  String daysAgo(int days) =>
      now.subtract(Duration(days: days)).toIso8601String();

  return [
    Quote(
      id: 'seed-excerpt-turkle',
      content: '沉浸在连接中却感到孤立，技术承诺免除脆弱的陪伴。我们期待技术能替代真实的人际投入，却忘记了独处才是反思的起点。',
      date: daysAgo(12),
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
      date: daysAgo(10),
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
      date: daysAgo(8),
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
      date: daysAgo(7),
      sourceAuthor: '卡尔·奥诺雷',
      sourceWork: '慢活',
      tagIds: const ['tag-reading-1', 'tag-philosophy'],
      weather: 'clear',
      dayPeriod: 'morning',
      location: '杭州·西湖区',
      temperature: '22°C',
    ),
    Quote(
      id: 'seed-own-commute',
      content:
          '早高峰地铁上又在想那个微内核架构与单体解耦的事情。警惕过早引入分布式服务，往往简单的单体加清晰的模块边界才是最稳健的。到公司被琐事一冲，差点忘了记录。',
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
          '连续三天下午三点后才能完全进入心流状态。早上的碎片化会议严重破坏了深度思考，打算下周把所有的沟通集中在上午，把下午的时间留给编码。',
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
          '读完塞内加的随笔后深夜失眠。总觉得有很多书没读、很多技术方案没写，这种对时间流逝的焦虑本质上是对失控的恐惧。学会接纳当下，哪怕只专注做好一件事。',
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
          '清晨在咖啡馆喝拿铁，阳光透进窗户。突然意识到 Local-First 应用最难的不是数据存储，而是多端冲突时的确定性反馈，必须让用户完全信任数据绝不会丢失。',
      date: daysAgo(3),
      tagIds: const ['tag-product', 'tag-tech'],
      weather: 'clear',
      dayPeriod: 'morning',
      location: '杭州·咖啡馆',
      temperature: '21°C',
    ),
    Quote(
      id: 'seed-signed-writing',
      content: '写下来的那一刻，混乱的念头才被赋予了骨骼。文字是时间的锚点，不需要写给别人看，诚实地记录真实的自己就足够了。',
      date: daysAgo(2),
      sourceAuthor: '阿澈',
      tagIds: const ['tag-daily', 'tag-philosophy'],
      weather: 'drizzle',
      dayPeriod: 'dusk',
      location: '杭州·西湖区',
      temperature: '19°C',
    ),
    Quote(
      id: 'seed-signed-tech-creed',
      content: '不要为了炫技而引入复杂的分布式状态机。最稳妥的架构往往是无状态的单向数据流与确定性的日志。',
      date: daysAgo(1),
      sourceAuthor: '阿澈',
      sourceWork: '阿澈的代码手记',
      tagIds: const ['tag-tech', 'tag-work'],
      weather: 'sunny',
      dayPeriod: 'afternoon',
      location: '杭州·海创园',
      temperature: '26°C',
    ),
  ];
}

const seedTags = [
  (id: 'tag-reading-1', name: '读书'),
  (id: 'tag-reading-2', name: '读书'),
  (id: 'tag-daily', name: '日常随笔'),
  (id: 'tag-tech', name: '技术思考'),
  (id: 'tag-philosophy', name: '斯多葛与哲学'),
  (id: 'tag-product', name: '产品与设计'),
  (id: 'tag-work', name: '工作复盘'),
];

Future<void> flagNoteContentLeaked(
  AgentMemoryService memory,
  ProbeTurn turn,
) async {
  const noteOnlyPhrases = [
    '地铁',
    '接口',
    '下午三点',
    '群体性孤独',
    '慢活',
    '塞内加',
    '论生命之短暂',
    '短促',
    '乔布斯',
    'WWDC',
    '微内核',
    '心流',
    '拿铁',
    'Local-First',
    '分布式状态机',
    '海创园',
    '阿里中心',
    '文三路',
    '单体解耦',
    '骨骼',
  ];
  final profile = await memory.activeProfile();
  final facts = await memory.searchFacts('', limit: 50);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Challenger M1 Empirical Verification', () {
    test('1. seedNotes validity, date format, and attributionKind', () {
      final notes = getSeedNotes();
      expect(notes.length, equals(10));

      final validTagIds = seedTags.map((t) => t.id).toSet();

      for (final note in notes) {
        // Validation check
        expect(note.isValid, isTrue,
            reason:
                'Note ${note.id} validation failed: ${note.validationError}');
        expect(note.content, isNotEmpty);
        expect(Quote.isValidDate(note.date), isTrue);

        // Safe delta ops check
        final ops = note.safeDeltaOps;
        expect(ops, isNotEmpty);

        // Tag ID validity
        for (final tagId in note.tagIds) {
          expect(validTagIds.contains(tagId), isTrue,
              reason: 'Note ${note.id} has unknown tagId $tagId');
        }
      }

      // Check Excerpts (4 items)
      final excerpts = notes.take(4).toList();
      for (final note in excerpts) {
        expect(note.hasAttribution, isTrue,
            reason: 'Excerpt ${note.id} must have attribution');
        expect(note.attributionKind, equals('excerpt'),
            reason: 'Excerpt ${note.id} attributionKind must be excerpt');
        expect(note.sourceAuthor, isNotNull);
        expect(note.sourceWork, isNotNull);
      }

      // Check Unauthored Originals (4 items)
      final unauthored = notes.skip(4).take(4).toList();
      for (final note in unauthored) {
        expect(note.hasAttribution, isFalse,
            reason: 'Unauthored note ${note.id} must NOT have attribution');
        expect(note.attributionKind, equals('original'),
            reason:
                'Unauthored note ${note.id} attributionKind must be original');
        expect(note.sourceAuthor, isNull);
        expect(note.sourceWork, isNull);
      }

      // Check User-Signed Originals (2 items)
      final signed = notes.skip(8).take(2).toList();
      for (final note in signed) {
        expect(note.hasAttribution, isTrue,
            reason:
                'Signed note ${note.id} has author so hasAttribution is true');
        expect(note.attributionKind, equals('excerpt'),
            reason:
                'Signed note attributionKind evaluates to excerpt by default in model');
        expect(note.sourceAuthor, equals('阿澈'));
      }
    });

    test(
        '2. _flagNoteContentLeakedIntoMemory clean and injected leak detection',
        () async {
      final settings = _MockSettingsService();
      final memory = AgentMemoryService(
        settingsService: settings,
        databasePath: inMemoryDatabasePath,
      );

      // Clean state test
      final cleanTurn = ProbeTurn(1, 'Clean Test');
      await flagNoteContentLeaked(memory, cleanTurn);
      expect(cleanTurn.findings, isEmpty);

      // Normal preference (non-leak)
      await memory.rememberProfile(
        directive: '回复尽量精炼，使用短句',
        kind: AgentMemoryKind.style,
      );
      await memory.addFact(
        content: '用户偏好使用简洁的中文沟通',
        category: 'preference',
      );
      final normalTurn = ProbeTurn(2, 'Normal Preference Test');
      await flagNoteContentLeaked(memory, normalTurn);
      expect(normalTurn.findings, isEmpty,
          reason: 'Normal preferences should not trigger leak detector');

      // Test all 20 note phrases injected into memory
      const phrases = [
        '地铁',
        '接口',
        '下午三点',
        '群体性孤独',
        '慢活',
        '塞内加',
        '论生命之短暂',
        '短促',
        '乔布斯',
        'WWDC',
        '微内核',
        '心流',
        '拿铁',
        'Local-First',
        '分布式状态机',
        '海创园',
        '阿里中心',
        '文三路',
        '单体解耦',
        '骨骼',
      ];

      for (var i = 0; i < phrases.length; i++) {
        final phrase = phrases[i];
        final testSettings = _MockSettingsService();
        final testMemory = AgentMemoryService(
          settingsService: testSettings,
          databasePath: inMemoryDatabasePath,
        );

        if (i % 2 == 0) {
          // Inject into facts
          await testMemory.addFact(
            content: '关于 $phrase 的思考记录',
            category: 'notes',
          );
        } else {
          // Inject into profile
          await testMemory.rememberProfile(
            directive: '用户提到了 $phrase 相关的内容',
            kind: AgentMemoryKind.feedback,
          );
        }

        final leakTurn = ProbeTurn(i + 3, 'Leak Test for $phrase');
        await flagNoteContentLeaked(testMemory, leakTurn);
        expect(leakTurn.findings.length, equals(1),
            reason: 'Should detect leak for phrase: $phrase');
        expect(leakTurn.findings.first, contains(phrase));

        testMemory.dispose();
      }

      memory.dispose();
    });
  });
}
