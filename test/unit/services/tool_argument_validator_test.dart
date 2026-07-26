import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/agent_tools/tool_argument_validator.dart';

const _schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'proposal_title': {'type': 'string'},
    'document_kind': {
      'type': 'string',
      'enum': ['plain', 'rich'],
    },
    'limit': {'type': 'integer'},
    'tag_ids': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': ['proposal_title', 'document_kind'],
};

String? _validate(Map<String, Object?> arguments) => validateToolArguments(
      toolName: 'propose_note_create',
      schema: _schema,
      arguments: arguments,
    );

void main() {
  group('validateToolArguments', () {
    test('accepts valid arguments', () {
      expect(
        _validate(const {
          'proposal_title': '标题',
          'document_kind': 'plain',
          'limit': 5,
          'tag_ids': ['t1'],
        }),
        isNull,
      );
    });

    test('reports missing required fields in Chinese', () {
      final error = _validate(const {'document_kind': 'plain'});
      expect(error, contains('缺少必填参数：proposal_title'));
      expect(error, contains('propose_note_create'));
    });

    test('reports unknown fields together with the accepted ones', () {
      final error = _validate(const {
        'proposal_title': '标题',
        'document_kind': 'rich',
        'document_ops': [<String, Object?>{}],
      });
      expect(error, contains('不支持的参数：document_ops'));
      // 顺带告诉模型正确字段叫什么
      expect(error, contains('tag_ids'));
    });

    test('reports type mismatches and enum violations', () {
      final error = _validate(const {
        'proposal_title': '标题',
        'document_kind': 'markdown',
        'limit': '五条',
      });
      expect(error, contains('类型不匹配'));
      expect(error, contains('limit（应为 整数，实际是 字符串）'));
      expect(error, contains('document_kind（只能是 plain、rich 之一'));
    });

    test('aggregates all three categories into one actionable message', () {
      final error = _validate(const {
        'document_kind': 'markdown',
        'stray': 1,
      });
      expect(error, contains('缺少必填参数'));
      expect(error, contains('不支持的参数'));
      expect(error, contains('类型不匹配'));
      expect(error!.split('\n'), hasLength(1));
    });
  });
}
