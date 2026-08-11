import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/explore_notes_tool.dart';
import 'package:thoughtecho/services/database_service.dart';

import '../../test_harness.dart';

class _TestDatabaseService extends DatabaseService {
  _TestDatabaseService(this._quotes) : super.forTesting();

  final List<Quote> _quotes;

  List<Quote> _filteredAndSorted({String? searchQuery}) {
    var rows = List<Quote>.from(_quotes);
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      rows = rows.where((e) => e.content.toLowerCase().contains(q)).toList();
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  @override
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    String? dateStart,
    String? dateEnd,
    bool includeDeleted = false,
  }) async {
    return _filteredAndSorted(searchQuery: searchQuery).length;
  }

  @override
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    String? dateStart,
    String? dateEnd,
    bool includeDeleted = false,
  }) async {
    final rows = _filteredAndSorted(searchQuery: searchQuery);
    if (offset >= rows.length) {
      return <Quote>[];
    }
    final end = (offset + limit).clamp(0, rows.length);
    return rows.sublist(offset, end);
  }

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
  Future<List<NoteTag>> getTags() async {
    return const <NoteTag>[];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('ExploreNotesTool', () {
    late ExploreNotesTool tool;
    late List<Quote> quotes;

    setUp(() {
      quotes = <Quote>[];
      for (var i = 0; i < 30; i++) {
        quotes.add(
          Quote(
            id: 'note_$i',
            content: 'keyword item $i ${List<String>.filled(180, 'x').join()}',
            date: DateTime(2026, 1, 30 - i, 12, i).toIso8601String(),
            location: 'loc_$i',
            poiName: 'poi_$i',
          ),
        );
      }
      tool = ExploreNotesTool(_TestDatabaseService(quotes));
    });

    test('returns paged payload with pagination info', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_1',
          name: 'explore_notes',
          arguments: const {
            'query': 'keyword',
            'limit': 5,
            'offset': 0,
          },
        ),
      );

      expect(result.isError, isFalse);
      final data = jsonDecode(result.content);
      expect(data['notes'], hasLength(5));
      expect(data['pagination']['offset'], 0);
      expect(data['pagination']['next_offset'], 5);
      expect(data['pagination']['has_more'], isTrue);
      expect(data['pagination']['total_count'], 30);
    });

    test('supports empty query for browsing', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_2',
          name: 'explore_notes',
          arguments: const {
            'limit': 10,
          },
        ),
      );

      expect(result.isError, isFalse);
      final data = jsonDecode(result.content);
      expect(data['notes'], hasLength(10));
    });

    test('零命中的关键词检索回带下一步提示，命中的不带', () async {
      final miss = await tool.execute(
        ToolCall(
          id: 'call_miss',
          name: 'explore_notes',
          arguments: const {'query': '这个词库里绝对没有'},
        ),
      );
      expect(miss.isError, isFalse);
      final missData = jsonDecode(miss.content) as Map<String, dynamic>;
      expect(missData['notes'], isEmpty);
      // 零命中是模型最容易就地下「你没写过 X」结论的地方，结果里必须说明
      // query 只是子串匹配，并给出改成浏览的出路。
      expect(missData['hint'], contains('子串匹配'));
      expect(missData['hint'], contains('浏览'));

      final hit = await tool.execute(
        ToolCall(
          id: 'call_hit',
          name: 'explore_notes',
          arguments: const {'query': 'keyword', 'limit': 5},
        ),
      );
      expect(
        (jsonDecode(hit.content) as Map<String, dynamic>).containsKey('hint'),
        isFalse,
      );
    });

    test('翻页翻过尾巴的空页不算零命中，不回带提示', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_past_end',
          name: 'explore_notes',
          arguments: const {'query': 'keyword', 'limit': 5, 'offset': 999},
        ),
      );

      final data = jsonDecode(result.content) as Map<String, dynamic>;
      expect(data['notes'], isEmpty);
      expect(data.containsKey('hint'), isFalse);
    });

    test('returns author and source as separate fields', () async {
      quotes
        ..clear()
        ..add(
          Quote(
            id: 'excerpt',
            content: '一段话',
            date: DateTime(2026, 1, 1).toIso8601String(),
            sourceAuthor: '作者甲',
            sourceWork: '作品乙',
          ),
        )
        ..add(
          Quote(
            id: 'legacy',
            content: '旧数据',
            date: DateTime(2026, 1, 2).toIso8601String(),
            source: '作者丙 - 作品丁',
          ),
        )
        ..add(
          Quote(
            id: 'plain',
            content: '无归属',
            date: DateTime(2026, 1, 3).toIso8601String(),
          ),
        );

      final result = await tool.execute(
        ToolCall(
          id: 'call_meta',
          name: 'explore_notes',
          arguments: const {'limit': 10},
        ),
      );

      expect(result.isError, isFalse);
      final notes =
          (jsonDecode(result.content) as Map<String, dynamic>)['notes'] as List;
      final byId = <String, Map<String, dynamic>>{
        for (final n in notes) (n as Map<String, dynamic>)['id'] as String: n,
      };

      final excerpt = byId['excerpt']!;
      expect(excerpt['author'], '作者甲');
      expect(excerpt['source'], '作品乙');

      // 只有合并 source 串的旧数据回退到 source，不重复填 author。
      final legacy = byId['legacy']!;
      expect(legacy['author'], isNull);
      expect(legacy['source'], '作者丙 - 作品丁');

      final plain = byId['plain']!;
      expect(plain.containsKey('author'), isFalse);
      expect(plain.containsKey('source'), isFalse);
    });

    test('returns snippet around query match in long content', () async {
      final prefix = List<String>.filled(260, '前').join();
      final suffix = List<String>.filled(260, '后').join();
      quotes
        ..clear()
        ..add(
          Quote(
            id: 'late_match',
            content: '$prefix important keyword $suffix',
            date: DateTime(2026, 1, 1).toIso8601String(),
          ),
        );

      final result = await tool.execute(
        ToolCall(
          id: 'call_snippet',
          name: 'explore_notes',
          arguments: const {
            'query': 'important keyword',
            'limit': 1,
          },
        ),
      );

      expect(result.isError, isFalse);
      final data = jsonDecode(result.content) as Map<String, dynamic>;
      final notes = data['notes'] as List;
      final note = notes.single as Map<String, dynamic>;
      expect(note['match_snippet'], contains('important keyword'));
      expect(note['content_preview'], isNot(contains('important keyword')));
      expect(note['is_truncated'], isTrue);
      expect(note['match_start'], prefix.length + 1);
    });
  });
}
