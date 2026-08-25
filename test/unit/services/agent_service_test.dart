import 'package:flutter_test/flutter_test.dart';
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
}
