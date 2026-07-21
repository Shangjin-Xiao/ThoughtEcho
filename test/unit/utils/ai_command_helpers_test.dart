import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/ai_command_helpers.dart';
import 'dart:convert';

void main() {
  group('WebCommandHelper', () {
    test('extractUrl should extract URL from /web command', () {
      expect(WebCommandHelper.extractUrl('/web https://example.com'),
          'https://example.com');
      expect(WebCommandHelper.extractUrl('/web: http://example.org'),
          'http://example.org');
      expect(WebCommandHelper.extractUrl('/web example.com'),
          'https://example.com');
      expect(WebCommandHelper.extractUrl('  /web   example.com  '),
          'https://example.com');
    });

    test('extractUrl should return null for invalid inputs', () {
      expect(WebCommandHelper.extractUrl('not a command'), isNull);
      expect(WebCommandHelper.extractUrl('/web'), isNull);
      expect(WebCommandHelper.extractUrl('/web: '), isNull);
    });

    test('extractUrlFromNaturalLanguage should extract URLs', () {
      expect(
          WebCommandHelper.extractUrlFromNaturalLanguage(
              'Check out https://example.com now'),
          'https://example.com');
      expect(
          WebCommandHelper.extractUrlFromNaturalLanguage(
              'URL: http://test.com, see this.'),
          'http://test.com');
      expect(
          WebCommandHelper.extractUrlFromNaturalLanguage(
              'Check https://example.com/path?q=1.'),
          'https://example.com/path?q=1.');
      expect(WebCommandHelper.extractUrlFromNaturalLanguage('No url here'),
          isNull);
    });
  });

  group('NoteQueryHelper', () {
    test('createSearchNotesToolParams should build correct map', () {
      final dateStart = DateTime(2023, 1, 1);
      final params = NoteQueryHelper.createSearchNotesToolParams(
        query: 'test',
        tags: ['tag1', 'tag2'],
        dateStart: dateStart,
        limit: 10,
      );

      expect(params['query'], 'test');
      expect(params['tags'], ['tag1', 'tag2']);
      expect(params['date_start'], dateStart.toIso8601String());
      expect(params.containsKey('date_end'), isFalse);
      expect(params['limit'], 10);
    });

    test('formatNotesForAgent should format note map properly', () {
      final notes = [
        {
          'id': 'note1',
          'content': 'Hello world\nThis is a test note.',
          'date': '2023-10-10',
          'keywords': 'ai, flutter',
          'summary': 'A test summary',
          'sentiment': 'positive'
        }
      ];

      final formatted = NoteQueryHelper.formatNotesForAgent(
        notes,
        tagsList: [
          ['tagA']
        ],
        matchScores: [0.95],
      );

      expect(formatted.length, 1);
      expect(formatted[0]['id'], 'note1');
      expect(formatted[0]['title'], 'Hello world');
      expect(formatted[0]['content'], 'Hello world\nThis is a test note.');
      expect(formatted[0]['tags'], ['tagA']);
      expect(formatted[0]['createdAt'], '2023-10-10');
      expect(formatted[0]['matchScore'], 0.95);
      expect(formatted[0]['summary'], 'A test summary');
      expect(formatted[0]['sentiment'], 'positive');
      expect(formatted[0]['keywords'], ['ai', 'flutter']);
    });

    test('formatNotesForAgent should handle missing optional fields', () {
      final notes = [
        {'id': 'note2'}
      ];
      final formatted = NoteQueryHelper.formatNotesForAgent(notes);

      expect(formatted[0]['id'], 'note2');
      expect(formatted[0]['title'], '');
      expect(formatted[0]['tags'], []);
      expect(formatted[0]['matchScore'], 1.0);
      expect(formatted[0]['keywords'], []);
    });
  });

  group('SessionMessageHelper', () {
    test('createToolCallIndicatorMessage should create valid message', () {
      final msg = SessionMessageHelper.createToolCallIndicatorMessage(
        toolName: 'search_notes',
        parameters: {'query': 'test'},
      );

      expect(msg.isUser, isFalse);
      expect(msg.role, 'assistant');
      expect(msg.content, '[正在调用] search_notes(query="test")');

      final meta = jsonDecode(msg.metaJson!);
      expect(meta['type'], 'tool_call_indicator');
      expect(meta['tool_name'], 'search_notes');
      expect(meta['parameters']['query'], 'test');
    });

    test('createToolResultMessage should create valid message on success', () {
      final msg = SessionMessageHelper.createToolResultMessage(
        toolName: 'search_notes',
        result: 'found 2 notes',
        isError: false,
      );

      expect(msg.isUser, isFalse);
      expect(msg.role, 'assistant');
      expect(msg.content, '[工具结果完成]\nfound 2 notes');

      final meta = jsonDecode(msg.metaJson!);
      expect(meta['type'], 'tool_result');
      expect(meta['tool_name'], 'search_notes');
      expect(meta['is_error'], isFalse);
    });

    test('createToolResultMessage should create valid message on error', () {
      final msg = SessionMessageHelper.createToolResultMessage(
        toolName: 'search_notes',
        result: 'timeout',
        isError: true,
      );

      expect(msg.content, '工具执行出错: timeout');

      final meta = jsonDecode(msg.metaJson!);
      expect(meta['is_error'], isTrue);
    });
  });
}
