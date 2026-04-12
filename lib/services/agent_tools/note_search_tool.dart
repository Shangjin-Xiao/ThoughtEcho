import 'dart:convert';

import '../../models/quote_model.dart';
import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import '../database_service.dart';

/// 搜索用户笔记内容（分页 + 增量全文拉取）
///
/// 目标：
/// 1. 不把全部笔记直接塞进上下文
/// 2. 搜索结果遵循字符预算，防止上下文过载
/// 3. 需要全文时按块增量拉取单条笔记
class NoteSearchTool extends AgentTool {
  static const int _defaultTargetChars = 2400;
  static const int _minTargetChars = 900;
  static const int _maxTargetChars = 12000;

  static const int _defaultChunkChars = 1400;
  static const int _minChunkChars = 400;
  static const int _maxChunkChars = 4000;

  static const int _minPageSize = 2;
  static const int _maxPageSize = 50;
  static const int _defaultSnippetChars = 220;
  static const int _minSnippetChars = 100;
  static const int _maxSnippetChars = 360;
  static const int _summaryMaxChars = 80;

  final DatabaseService _db;
  const NoteSearchTool(this._db);

  @override
  String get name => 'search_notes';

  @override
  String get description => '【只读】搜索用户笔记并返回分页摘要；可按需增量拉取单条笔记全文片段。此工具没有任何修改权限。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['search', 'fetch_note'],
            'description': 'search=分页检索，fetch_note=按块拉取单条笔记',
          },
          'query': {
            'type': 'string',
            'description': '搜索关键词（action=search 必填）',
          },
          'cursor': {
            'type': ['object', 'string', 'null'],
            'description': '翻页游标，来自上一页 next_cursor',
          },
          'next_cursor': {
            'type': ['object', 'string', 'null'],
            'description': '兼容字段：等价于 cursor，支持直接透传上一页 next_cursor',
          },
          'target_chars': {
            'type': 'integer',
            'description': '本次结果字符预算（默认 2400）',
          },
          'requested_page_size': {
            'type': 'integer',
            'description': '期望页大小，最终会按预算自适应调整',
          },
          'snippet_chars': {
            'type': 'integer',
            'description': '每条摘要长度上限（默认自适应）',
          },
          'note_id': {
            'type': 'string',
            'description': '要增量拉取的笔记 ID（action=fetch_note 必填）',
          },
          'offset_chars': {
            'type': 'integer',
            'description': '增量拉取起始偏移，默认 0',
          },
          'chunk_chars': {
            'type': 'integer',
            'description': '本次拉取的字符块大小（默认 1400）',
          },
          'around_query': {
            'type': 'string',
            'description': 'fetch_note 时可选：优先围绕关键词定位首块',
          },
        },
        'required': ['action'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final action =
        (call.arguments['action'] as String? ?? 'search').trim().toLowerCase();

    try {
      return switch (action) {
        'search' => await _executeSearch(call),
        'fetch_note' => await _executeFetchNote(call),
        _ => ToolResult(
            toolCallId: call.id,
            content: '不支持的 action: $action。仅支持 search / fetch_note',
            isError: true,
          ),
      };
    } catch (e, stack) {
      logError('NoteSearchTool.execute 失败', error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '搜索笔记时出错：$e',
        isError: true,
      );
    }
  }

  Future<ToolResult> _executeSearch(ToolCall call) async {
    final query = (call.arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'action=search 时 query 不能为空',
        isError: true,
      );
    }

    final targetChars = _intArg(
      call.arguments['target_chars'],
      fallback: _defaultTargetChars,
      min: _minTargetChars,
      max: _maxTargetChars,
    );
    final requestedPageSize = _intArg(
      call.arguments['requested_page_size'],
      fallback: 0,
      min: 0,
      max: _maxPageSize,
    );
    final snippetChars = _intArg(
      call.arguments['snippet_chars'],
      fallback: _defaultSnippetChars,
      min: _minSnippetChars,
      max: _maxSnippetChars,
    );
    final cursor = _parseCursor(call.arguments);

    final pageSize = _adaptivePageSize(
      targetChars: targetChars,
      snippetChars: snippetChars,
      requestedPageSize: requestedPageSize == 0 ? null : requestedPageSize,
    );

    final totalMatches = await _db.getQuotesCount(searchQuery: query);
    final quotes = await _db.getUserQuotes(
      searchQuery: query,
      orderBy: 'date DESC',
      offset: cursor?.offset ?? 0,
      limit: pageSize + 1,
    );

    final dbHasMore = quotes.length > pageSize;
    final pageQuotes = dbHasMore ? quotes.sublist(0, pageSize) : quotes;

    final items = <Map<String, dynamic>>[];
    final metadataBudget = (targetChars * 0.72).round();
    var usedChars = 0;

    for (final quote in pageQuotes) {
      final item = _buildSearchItem(
          quote: quote, query: query, snippetChars: snippetChars);
      final estimatedChars = (item['summary'] as String).length +
          (item['snippet'] as String).length +
          120;
      if (items.isNotEmpty && usedChars + estimatedChars > metadataBudget) {
        break;
      }
      items.add(item);
      usedChars += estimatedChars;
    }

    final trimmedByBudget = items.length < pageQuotes.length;
    final hasMore = dbHasMore || trimmedByBudget;
    final nextOffset = (cursor?.offset ?? 0) + items.length;
    final nextCursor =
        hasMore && items.isNotEmpty ? _SearchCursor(offset: nextOffset) : null;

    final payload = <String, dynamic>{
      'mode': 'search_page',
      'query': query,
      'total_matches': totalMatches,
      'returned_items': items.length,
      'target_chars': targetChars,
      'has_more': hasMore,
      'next_cursor': nextCursor?.toJson(),
      'items': items,
      'guide': {
        'next': hasMore ? '使用 action=search 并传入 next_cursor 继续翻页' : '无更多分页结果',
        'detail': '需要全文时使用 action=fetch_note + note_id 按块拉取',
      },
    };

    var encoded = jsonEncode(payload);
    payload['response_chars'] = encoded.length;
    encoded = jsonEncode(payload);

    return ToolResult(toolCallId: call.id, content: encoded);
  }

  Future<ToolResult> _executeFetchNote(ToolCall call) async {
    final noteId = (call.arguments['note_id'] as String? ?? '').trim();
    if (noteId.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'action=fetch_note 时 note_id 不能为空',
        isError: true,
      );
    }

    final chunkChars = _intArg(
      call.arguments['chunk_chars'],
      fallback: _defaultChunkChars,
      min: _minChunkChars,
      max: _maxChunkChars,
    );
    final aroundQuery =
        (call.arguments['around_query'] as String? ?? '').trim();
    var offsetChars = _intArg(
      call.arguments['offset_chars'],
      fallback: 0,
      min: 0,
      max: 1 << 30,
    );

    final quote = await _db.getQuoteById(noteId);
    if (quote == null) {
      return ToolResult(
        toolCallId: call.id,
        content: '未找到 ID 为 $noteId 的笔记',
        isError: true,
      );
    }

    final content = quote.content;
    final totalChars = content.length;

    if (offsetChars == 0 && aroundQuery.isNotEmpty) {
      final idx = _indexOfIgnoreCase(content, aroundQuery);
      if (idx >= 0) {
        offsetChars = (idx - chunkChars ~/ 3).clamp(0, totalChars);
      }
    }
    offsetChars = offsetChars.clamp(0, totalChars);

    final end = (offsetChars + chunkChars).clamp(0, totalChars);
    final chunk = content.substring(offsetChars, end);
    final done = end >= totalChars;

    final payload = <String, dynamic>{
      'mode': 'note_chunk',
      'note_id': noteId,
      'date': quote.date,
      'offset_chars': offsetChars,
      'next_offset_chars': done ? totalChars : end,
      'chunk_chars': chunk.length,
      'total_chars': totalChars,
      'done': done,
      'chunk_text': chunk,
      'guide': done ? '已到文末' : '继续传入 next_offset_chars 以增量获取后续内容',
    };

    return ToolResult(
      toolCallId: call.id,
      content: jsonEncode(payload),
    );
  }

  static Map<String, dynamic> _buildSearchItem({
    required Quote quote,
    required String query,
    required int snippetChars,
  }) {
    final content = quote.content;
    final item = <String, dynamic>{
      'id': quote.id ?? '',
      'date': quote.date,
      'summary': _buildSummary(content),
      'snippet': _buildSnippet(content, query, snippetChars),
      'content_chars': content.length,
    };

    final location = (quote.poiName ?? quote.location ?? '').trim();
    if (location.isNotEmpty) {
      item['location'] = location;
    }
    return item;
  }

  static int _intArg(
    Object? value, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final parsed = (value as num?)?.toInt() ?? fallback;
    return parsed.clamp(min, max).toInt();
  }

  static _SearchCursor? _parseCursor(Map<String, Object?> arguments) {
    final directCursor = _SearchCursor.fromUnknown(arguments['cursor']);
    if (directCursor != null) {
      return directCursor;
    }
    return _SearchCursor.fromUnknown(arguments['next_cursor']);
  }

  static int _adaptivePageSize({
    required int targetChars,
    required int snippetChars,
    int? requestedPageSize,
  }) {
    final perItemBudget = snippetChars + 180;
    final byBudget = (targetChars ~/ perItemBudget).clamp(
      _minPageSize,
      _maxPageSize,
    );
    if (requestedPageSize == null) {
      return byBudget;
    }
    return requestedPageSize.clamp(_minPageSize, byBudget).toInt();
  }

  static String _buildSummary(String content) {
    if (content.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    var index = 0;
    var wroteWhitespace = false;

    while (index < content.length && buffer.length < _summaryMaxChars) {
      final unit = content.codeUnitAt(index);
      if (_isWhitespace(unit)) {
        if (!wroteWhitespace && buffer.isNotEmpty) {
          buffer.write(' ');
        }
        wroteWhitespace = true;
      } else {
        buffer.writeCharCode(unit);
        wroteWhitespace = false;
      }
      index++;
    }

    var summary = buffer.toString().trimRight();
    if (_hasNonWhitespaceFrom(content, index)) {
      summary = '$summary…';
    }
    return summary;
  }

  static String _buildSnippet(String content, String query, int snippetChars) {
    if (content.isEmpty) {
      return '';
    }

    final idx = _indexOfIgnoreCase(content, query);

    if (idx < 0) {
      return content.length <= snippetChars
          ? content
          : '${content.substring(0, snippetChars)}…';
    }

    final half = snippetChars ~/ 2;
    final start = (idx - half).clamp(0, content.length);
    final end = (start + snippetChars).clamp(0, content.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < content.length ? '…' : '';
    return '$prefix${content.substring(start, end)}$suffix';
  }

  static int _indexOfIgnoreCase(String content, String query) {
    if (query.isEmpty) {
      return -1;
    }
    final match = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).firstMatch(content);
    return match?.start ?? -1;
  }

  static bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D ||
        codeUnit == 0x0C;
  }

  static bool _hasNonWhitespaceFrom(String content, int start) {
    for (var i = start; i < content.length; i++) {
      if (!_isWhitespace(content.codeUnitAt(i))) {
        return true;
      }
    }
    return false;
  }
}

class _SearchCursor {
  const _SearchCursor({
    required this.offset,
  });

  final int offset;

  Map<String, int> toJson() => {'offset': offset};

  static _SearchCursor? fromUnknown(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is Map) {
      final offset = (value['offset'] as num?)?.toInt() ?? 0;
      if (offset < 0) {
        return null;
      }
      return _SearchCursor(offset: offset);
    }

    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return fromUnknown(decoded);
        }
      } catch (_) {
        return null;
      }
    }

    return null;
  }
}
