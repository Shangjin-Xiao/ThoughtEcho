import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/get_note_detail_tool.dart';
import 'package:thoughtecho/services/database_service.dart';

import '../../test_harness.dart';

class _TestDatabaseService extends DatabaseService {
  _TestDatabaseService(this._quotes) : super.forTesting();

  final List<Quote> _quotes;
  int getTagsByIdsCallCount = 0;

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
  Future<NoteTag?> getTagById(String id) async {
    if (id == 'cat_work') {
      return NoteTag(id: 'cat_work', name: '工作', isDefault: false);
    }
    if (id == 'tag_idea') {
      return NoteTag(id: 'tag_idea', name: '灵感', isDefault: false);
    }
    if (id == 'tag_life') {
      return NoteTag(id: 'tag_life', name: '生活', isDefault: false);
    }
    return null;
  }

  @override
  Future<Map<String, NoteTag>> getTagsByIds(Iterable<String> ids) async {
    getTagsByIdsCallCount++;
    final result = <String, NoteTag>{};
    for (final id in ids) {
      final tag = await getTagById(id);
      if (tag != null) {
        result[id] = tag;
      }
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('GetNoteDetailTool', () {
    late GetNoteDetailTool tool;
    late List<Quote> quotes;

    setUp(() {
      quotes = <Quote>[
        Quote(
          id: 'note_123',
          content:
              'This is a very long note that needs to be fully read by the Agent for polishing.',
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

    test('returns full note details including all metadata and full content',
        () async {
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
      // 笔记正文是用户数据：包裹 <note> 标签，声明为数据而非指令
      expect(
        data['content'],
        '<note id="note_123">This is a very long note that needs to be '
        'fully read by the Agent for polishing.</note>',
      );
      expect(data['location'], 'Tsinghua University');
      expect(data['weather'], 'Sunny');
      expect(data['temperature'], '25°C');
      expect(data['category'], '工作');
      expect(data['tags'], contains('灵感'));
      expect(data['author'], 'Lu Xun');
      expect(data['source'], 'Diary of a Madman');
      expect(data['document_kind'], 'plain');
      expect(data.containsKey('document_ops'), isFalse);
      expect(data['document_revision'], matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('returns sanitized rich ops without exposing local media paths',
        () async {
      quotes.add(Quote(
        id: 'rich',
        content: 'Photo',
        date: '2026-06-06T12:00:00Z',
        editSource: 'fullscreen',
        deltaContent: jsonEncode(const [
          {'insert': 'Photo '},
          {
            'insert': {'image': '/home/user/private.jpg'}
          },
          {'insert': '\n'},
        ]),
      ));

      final result = await tool.execute(ToolCall(
        id: 'rich_detail',
        name: 'get_note_detail',
        arguments: const {'note_id': 'rich'},
      ));
      final data = jsonDecode(result.content) as Map<String, dynamic>;

      expect(data['document_kind'], 'rich');
      expect(data['document_ops'].toString(), contains('[media]'));
      expect(data['document_ops'].toString(), isNot(contains('/home/user')));
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

    test('fetches category and multiple tags in a single batch query call',
        () async {
      final testDb = _TestDatabaseService(<Quote>[
        Quote(
          id: 'note_multi_tags',
          content: 'Note with multiple tags',
          date: '2026-06-06T12:00:00Z',
          categoryId: 'cat_work',
          tagIds: const ['tag_idea', 'tag_life'],
        ),
      ]);
      final multiTool = GetNoteDetailTool(testDb);

      final result = await multiTool.execute(
        ToolCall(
          id: 'call_multi',
          name: 'get_note_detail',
          arguments: const {
            'note_id': 'note_multi_tags',
          },
        ),
      );

      expect(result.isError, isFalse);
      expect(testDb.getTagsByIdsCallCount, 1);
      final data = jsonDecode(result.content);
      expect(data['category'], '工作');
      expect(data['tags'], containsAll(['灵感', '生活']));
    });
  });
}
