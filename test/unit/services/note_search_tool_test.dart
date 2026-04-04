import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/note_search_tool.dart';
import 'package:thoughtecho/services/database_service.dart';

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
  }) async {
    final rows = _filteredAndSorted(searchQuery: searchQuery);
    if (offset >= rows.length) {
      return <Quote>[];
    }
    final end = (offset + limit).clamp(0, rows.length);
    return rows.sublist(offset, end);
  }

  @override
  Future<Quote?> getQuoteById(String id) async {
    for (final quote in _quotes) {
      if (quote.id == id) {
        return quote;
      }
    }
    return null;
  }
}

void main() {
  group('NoteSearchTool', () {
    late NoteSearchTool tool;
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
      tool = NoteSearchTool(_TestDatabaseService(quotes));
    });

    test('returns paged payload with cursor under target budget', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_1',
          name: 'search_notes',
          arguments: const {
            'action': 'search',
            'query': 'keyword',
            'target_chars': 900,
            'requested_page_size': 40,
          },
        ),
      );

      expect(result.isError, isFalse);
      final payload = jsonDecode(result.content) as Map<String, dynamic>;

      expect(payload['mode'], 'search_page');
      expect(payload['total_matches'], 30);
      expect(payload['returned_items'], greaterThan(0));
      expect(payload['next_cursor'], isNotNull);
      expect(payload['response_chars'], lessThanOrEqualTo(900));
    });

    test('supports incremental note content fetch', () async {
      final longContent =
          '${List<String>.filled(400, 'ABCD').join()} keyword pivot ${List<String>.filled(450, 'WXYZ').join()} tail';
      quotes.add(
        Quote(
          id: 'long_note',
          content: longContent,
          date: DateTime(2026, 3, 1, 8, 30).toIso8601String(),
          location: 'loc',
          poiName: 'poi',
        ),
      );

      final first = await tool.execute(
        ToolCall(
          id: 'call_2',
          name: 'search_notes',
          arguments: const {
            'action': 'fetch_note',
            'note_id': 'long_note',
            'chunk_chars': 700,
            'offset_chars': 0,
          },
        ),
      );
      expect(first.isError, isFalse);
      final firstPayload = jsonDecode(first.content) as Map<String, dynamic>;
      expect(firstPayload['mode'], 'note_chunk');
      expect(firstPayload['done'], isFalse);
      expect((firstPayload['chunk_text'] as String).length,
          lessThanOrEqualTo(700));

      final second = await tool.execute(
        ToolCall(
          id: 'call_3',
          name: 'search_notes',
          arguments: {
            'action': 'fetch_note',
            'note_id': 'long_note',
            'chunk_chars': 700,
            'offset_chars': firstPayload['next_offset_chars'],
          },
        ),
      );
      expect(second.isError, isFalse);
      final secondPayload = jsonDecode(second.content) as Map<String, dynamic>;
      expect(
        secondPayload['next_offset_chars'],
        greaterThan(firstPayload['next_offset_chars']),
      );
      expect(
        secondPayload['offset_chars'],
        firstPayload['next_offset_chars'],
      );
    });

    test('fetch_note positions first chunk around query case-insensitively',
        () async {
      final pivot = 'MiXeD-KeyWord';
      final longContent =
          '${List<String>.filled(700, 'A').join()} $pivot ${List<String>.filled(900, 'B').join()}';
      quotes.add(
        Quote(
          id: 'around_query_note',
          content: longContent,
          date: DateTime(2026, 3, 2, 8, 30).toIso8601String(),
          location: 'loc',
          poiName: 'poi',
        ),
      );

      final result = await tool.execute(
        ToolCall(
          id: 'call_4',
          name: 'search_notes',
          arguments: const {
            'action': 'fetch_note',
            'note_id': 'around_query_note',
            'chunk_chars': 500,
            'around_query': 'mixed-keyword',
          },
        ),
      );

      expect(result.isError, isFalse);
      final payload = jsonDecode(result.content) as Map<String, dynamic>;
      final chunkText = payload['chunk_text'] as String;
      expect(payload['offset_chars'], greaterThan(0));
      expect(chunkText.toLowerCase(), contains('mixed-keyword'));
    });
  });
}
