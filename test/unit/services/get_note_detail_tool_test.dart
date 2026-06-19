import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/get_note_detail_tool.dart';
import 'package:thoughtecho/services/database_service.dart';

import '../../test_helpers.dart';

class _TestDatabaseService extends DatabaseService {
  _TestDatabaseService(this._quotes) : super.forTesting();

  final List<Quote> _quotes;

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    for (final quote in _quotes) {
      if (quote.id == id) {
        return quote;
      }
    }
    return null;
  }

  @override
  Future<NoteCategory?> getCategoryById(String id) async {
    if (id == 'cat_work') {
      return NoteCategory(id: 'cat_work', name: '工作', isDefault: false);
    }
    if (id == 'tag_idea') {
      return NoteCategory(id: 'tag_idea', name: '灵感', isDefault: false);
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await TestHelpers.setupTestEnvironment();
  });

  group('GetNoteDetailTool', () {
    late GetNoteDetailTool tool;
    late List<Quote> quotes;

    setUp(() {
      quotes = <Quote>[
        Quote(
          id: 'note_123',
          content: 'This is a very long note that needs to be fully read by the Agent for polishing.',
          date: '2026-06-06T12:00:00Z',
          location: 'Beijing',
          poiName: 'Tsinghua University',
          weather: 'Sunny',
          temperature: '25°C',
          categoryId: 'cat_work',
          tagIds: const ['tag_idea'],
          sourceAuthor: 'Lu Xun',
          sourceWork: 'Diary of a Madman',
        ),
      ];
      tool = GetNoteDetailTool(_TestDatabaseService(quotes));
    });

    test('returns full note details including all metadata and full content', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_detail_1',
          name: 'get_note_detail',
          arguments: const {
            'note_id': 'note_123',
          },
        ),
      );

      expect(result.isError, isFalse);
      final data = jsonDecode(result.content);
      expect(data['id'], 'note_123');
      expect(data['content'], 'This is a very long note that needs to be fully read by the Agent for polishing.');
      expect(data['location'], 'Tsinghua University');
      expect(data['weather'], 'Sunny');
      expect(data['temperature'], '25°C');
      expect(data['category'], '工作');
      expect(data['tags'], contains('灵感'));
      expect(data['author'], 'Lu Xun');
      expect(data['source'], 'Diary of a Madman');
    });

    test('returns error if note_id is empty or missing', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_detail_2',
          name: 'get_note_detail',
          arguments: const {},
        ),
      );

      expect(result.isError, isTrue);
      expect(result.content, contains('note_id不能为空'));
    });

    test('returns error if note is not found', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_detail_3',
          name: 'get_note_detail',
          arguments: const {
            'note_id': 'non_existent_id',
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(result.content, contains('未找到ID为non_existent_id的笔记'));
    });
  });
}
