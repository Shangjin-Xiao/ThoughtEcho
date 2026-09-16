import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';

import '../../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('AgentService canonicalJsonForArguments', () {
    test('returns same key for same semantic arguments with different order',
        () {
      final argsA = <String, Object?>{
        'query': 'today',
        'limit': 10,
        'filters': <String, Object?>{
          'sort': 'desc',
          'tags': <Object?>['a', 'b'],
        },
      };

      final argsB = <String, Object?>{
        'limit': 10,
        'filters': <String, Object?>{
          'tags': <Object?>['a', 'b'],
          'sort': 'desc',
        },
        'query': 'today',
      };

      final keyA = AgentService.canonicalJsonForArguments(argsA);
      final keyB = AgentService.canonicalJsonForArguments(argsB);

      expect(keyA, equals(keyB));
    });
  });

  group('AgentTool immutability and deep equality', () {
    test('tool call arguments are deeply immutable', () {
      final call = ToolCall(
        id: '1',
        name: 'search_notes',
        arguments: <String, Object?>{
          'query': 'abc',
          'filters': <String, Object?>{
            'tags': <Object?>['x', 'y'],
          },
        },
      );

      expect(() => call.arguments['query'] = 'changed', throwsUnsupportedError);
      final nested = call.arguments['filters'] as Map<String, Object?>;
      expect(() => nested['tags'] = <Object?>['z'], throwsUnsupportedError);

      // Test nested List immutability
      final nestedList = nested['tags'] as List<Object?>;
      expect(() => nestedList[0] = 'changed', throwsUnsupportedError);
      expect(() => nestedList.add('z'), throwsUnsupportedError);
    });

    test('tool call deep equality ignores key order for nested maps', () {
      final a = ToolCall(
        id: '1',
        name: 'search_notes',
        arguments: <String, Object?>{
          'query': 'hello',
          'filters': <String, Object?>{
            'sort': 'desc',
            'tags': <Object?>['a', 'b'],
          },
        },
      );
      final b = ToolCall(
        id: '1',
        name: 'search_notes',
        arguments: <String, Object?>{
          'filters': <String, Object?>{
            'tags': <Object?>['a', 'b'],
            'sort': 'desc',
          },
          'query': 'hello',
        },
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('AgentService describeNow', () {
    test('renders date, weekday and day period key for the given time', () {
      // 2026-07-29 是周三，15:04 落在午后时段。
      final text = AgentService.describeNow(DateTime(2026, 7, 29, 15, 4));

      expect(text, contains('2026-07-29'));
      expect(text, contains('周三'));
      expect(text, contains('15:04'));
      expect(text, contains('afternoon'));
    });

    // 旧会话被重新打开时，历史里的"今天"不是现在的今天。
    test('flags a reopened session with the elapsed gap', () {
      final text = AgentService.describeHistoryGap(
        DateTime(2026, 7, 20, 9, 30),
        DateTime(2026, 7, 29, 15, 4),
      );

      expect(text, isNotNull);
      expect(text, contains('2026-07-20 09:30'));
      expect(text, contains('9 天前'));
    });

    test('stays quiet when the conversation is still fresh', () {
      expect(
        AgentService.describeHistoryGap(
          DateTime(2026, 7, 29, 12, 0),
          DateTime(2026, 7, 29, 15, 4),
        ),
        isNull,
      );
    });

    test('maps late night hours to the midnight period', () {
      expect(
        AgentService.describeNow(DateTime(2026, 1, 1, 2, 30)),
        contains('midnight'),
      );
      expect(
        AgentService.describeNow(DateTime(2026, 1, 1, 23, 0)),
        contains('midnight'),
      );
    });
  });

  // 知道今天几号还不够：模型仍要自己算周一是哪天，而它算错的代价是
  // 周一点「总结本周」时拿上周的笔记充数。边界直接写在提示里。
  group('AgentService describePeriodBounds', () {
    test('spells out this week, this month and this year', () {
      // 2026-08-24 是周一。
      final text = AgentService.describePeriodBounds(DateTime(2026, 8, 24, 9));

      expect(text, contains('2026-08-24 ~ 2026-08-30'));
      expect(text, contains('2026-08-01 ~ 2026-08-31'));
      expect(text, contains('2026-01-01 ~ 2026-12-31'));
    });

    // 探索页能翻到上周，快捷追问带进来的就是「总结上周」——上一档的边界
    // 也得给现成的，别留一步减法让模型自己算。
    test('spells out last week, last month and last year too', () {
      final text = AgentService.describePeriodBounds(DateTime(2026, 8, 24, 9));

      expect(text, contains('上周 2026-08-17 ~ 2026-08-23'));
      expect(text, contains('上月 2026-07-01 ~ 2026-07-31'));
      expect(text, contains('去年 2025-01-01 ~ 2025-12-31'));
    });

    test('last month rolls back across the year boundary', () {
      final text = AgentService.describePeriodBounds(DateTime(2026, 1, 15));
      expect(text, contains('上月 2025-12-01 ~ 2025-12-31'));
    });

    test('week starts on Monday even mid-week', () {
      // 2026-08-27 是周四，本周仍然是 24 到 30。
      final text = AgentService.describePeriodBounds(DateTime(2026, 8, 27, 22));
      expect(text, contains('2026-08-24 ~ 2026-08-30'));
    });

    test('a week spanning a month boundary keeps both ends', () {
      // 2026-09-01 是周二，本周从 8-31 跨到 9-6。
      final text = AgentService.describePeriodBounds(DateTime(2026, 9, 1));
      expect(text, contains('2026-08-31 ~ 2026-09-06'));
      expect(text, contains('2026-09-01 ~ 2026-09-30'));
    });
  });

  group('AgentService post-turn memory capture heuristics', () {
    test(
        'hasMemorySignal identifies corrections, identity, and explicit preferences',
        () {
      expect(AgentService.hasMemorySignal('以后回答简短一点，不要太长了'), isTrue);
      expect(AgentService.hasMemorySignal('你刚才记错了，纠偏一下'), isTrue);
      expect(AgentService.hasMemorySignal('不要每次都加上天气信息'), isTrue);
      expect(AgentService.hasMemorySignal('我是阿澈，以后叫我阿澈就好'), isTrue);
      expect(AgentService.hasMemorySignal('我是一名后端工程师，定居在杭州'), isTrue);
      expect(AgentService.hasMemorySignal('我更喜欢极简风格的排版'), isTrue);
      expect(AgentService.hasMemorySignal('我的文风偏向短句与白描'), isTrue);
      expect(AgentService.hasMemorySignal('我爱读博尔赫斯与卡尔维诺'), isTrue);
      expect(AgentService.hasMemorySignal('我主要做古建筑田野调查与营造法式研究'), isTrue);
      expect(AgentService.hasMemorySignal('叫我林晚就好'), isTrue);
      expect(AgentService.hasMemorySignal('我的笔名是林晚'), isTrue);
      expect(AgentService.hasMemorySignal('我关注民间传统风物与地方饮食谱系'), isTrue);
      expect(AgentService.hasMemorySignal('我的文字倾向于详实细腻的白描'), isTrue);
      expect(AgentService.hasMemorySignal('我转行做游戏开发了'), isTrue);
      expect(AgentService.hasMemorySignal('我改行了，现在做自由职业'), isTrue);
      expect(AgentService.hasMemorySignal('我不再做古建研究了'), isTrue);
      expect(AgentService.hasMemorySignal('我的职业是建筑修复师'), isTrue);
      expect(AgentService.hasMemorySignal('我擅长榫卯结构测绘'), isTrue);
      expect(AgentService.hasMemorySignal('请记住，我习惯早起写作'), isTrue);
      expect(AgentService.hasMemorySignal('Call me Alex from now on'), isTrue);
      expect(AgentService.hasMemorySignal("Don't add weather to my notes"),
          isTrue);
      expect(AgentService.hasMemorySignal('I prefer concise bullet points'),
          isTrue);
      expect(AgentService.hasMemorySignal('Please remember that I like poetry'),
          isTrue);
    });

    test('hasMemorySignal filters out casual chat, queries, and short commands',
        () {
      expect(AgentService.hasMemorySignal('你好'), isFalse);
      expect(AgentService.hasMemorySignal('在吗'), isFalse);
      expect(AgentService.hasMemorySignal('今天天气怎么样？'), isFalse);
      expect(AgentService.hasMemorySignal('帮我写一篇关于秋天的随笔'), isFalse);
      expect(AgentService.hasMemorySignal('搜索一下上周关于架构的笔记'), isFalse);
      expect(AgentService.hasMemorySignal('把这篇笔记导出为 PDF 文件'), isFalse);
      expect(AgentService.hasMemorySignal('谢谢，这篇写得很好！'), isFalse);
      expect(AgentService.hasMemorySignal('a' * 350),
          isFalse); // over length limit
    });

    test('parsePostTurnMemoryJson parses valid high-confidence JSON payload',
        () {
      const validJson = '''
      {
        "has_memory": true,
        "kind": "style",
        "directive": "回答保持精炼短句，避免空话",
        "confidence": 0.95
      }
      ''';
      final result = AgentService.parsePostTurnMemoryJson(validJson);
      expect(result, isNotNull);
      expect(result!.hasMemory, isTrue);
      expect(result.kind, equals(AgentMemoryKind.style));
      expect(result.directive, equals('回答保持精炼短句，避免空话'));
      expect(result.confidence, closeTo(0.95, 0.001));
    });

    test(
        'parsePostTurnMemoryJson correctly parses JSON wrapped in markdown formatting',
        () {
      const wrappedJson = '''
      ```json
      {
        "has_memory": true,
        "kind": "identity",
        "directive": "用户职业为后端架构师",
        "confidence": 0.90
      }
      ```
      ''';
      final result = AgentService.parsePostTurnMemoryJson(wrappedJson);
      expect(result, isNotNull);
      expect(result!.hasMemory, isTrue);
      expect(result.kind, equals(AgentMemoryKind.identity));
      expect(result.directive, equals('用户职业为后端架构师'));
      expect(result.confidence, closeTo(0.90, 0.001));
    });

    test('parsePostTurnMemoryJson handles has_memory false and invalid content',
        () {
      final noMemory =
          AgentService.parsePostTurnMemoryJson('{"has_memory": false}');
      expect(noMemory, isNotNull);
      expect(noMemory!.hasMemory, isFalse);

      expect(AgentService.parsePostTurnMemoryJson('这是一段普通文本没有JSON'), isNull);
      expect(AgentService.parsePostTurnMemoryJson('{corrupted json'), isNull);
    });
  });
}
