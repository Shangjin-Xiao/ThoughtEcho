import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';

void main() {
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
}
