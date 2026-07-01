import 'dart:convert';
import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import '../database_service.dart';
import 'tag_argument_resolver.dart';

/// 探索笔记工具 - 支持多维筛选与分页
///
/// 目标：
/// 1. 像用户浏览一样，通过时间、天气、标签、时段等维度探索笔记
/// 2. 支持分页，防止上下文过载
/// 3. 提供概览信息，让 AI 具备“主观能动性”去决定下一步动作
class ExploreNotesTool extends AgentTool {
  final DatabaseService _db;

  const ExploreNotesTool(this._db);

  @override
  String get name => 'explore_notes';

  @override
  String get description =>
      '【核心工具】像浏览一样探索、筛选和搜索用户笔记。支持多维组合筛选（关键词、标签、日期范围、天气、时段）和分页浏览。';

  @override
  bool get isReadOnly => true;

  @override
  bool get isConcurrencySafe => true;

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词（可选）',
          },
          'tag_names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标签名称列表（可选）',
          },
          'category_id': {
            'type': 'string',
            'description': '分类ID（可选）',
          },
          'date_start': {
            'type': 'string',
            'description': '开始日期 (ISO8601，如 2024-01-01)',
          },
          'date_end': {
            'type': 'string',
            'description': '结束日期 (ISO8601，如 2024-12-31)',
          },
          'weathers': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '天气列表（可选，如 ["sunny", "rainy"]）',
          },
          'day_periods': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '时段列表（可选，如 ["morning", "night"]）',
          },
          'offset': {
            'type': 'integer',
            'description': '分页偏移量，默认 0',
          },
          'limit': {
            'type': 'integer',
            'description': '返回数量 (1-20, 默认 10)',
          },
        },
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      final query = call.getString('query');
      final resolvedTags = await resolveTagArguments(_db, call.arguments);
      if (resolvedTags.hasError) {
        return ToolResult(
          toolCallId: call.id,
          content: resolvedTags.errorMessage!,
          isError: true,
          retryable: true,
        );
      }
      final tagIds = resolvedTags.ids.isEmpty ? null : resolvedTags.ids;
      final categoryId = call.getString('category_id');
      final dateStart = call.getString('date_start');
      final dateEnd = call.getString('date_end');
      final weathers =
          (call.arguments['weathers'] as List?)?.whereType<String>().toList();
      final dayPeriods = (call.arguments['day_periods'] as List?)
          ?.whereType<String>()
          .toList();
      final offset = call.getInt('offset', defaultValue: 0);
      final limit = call.getInt('limit', defaultValue: 10).clamp(1, 20).toInt();

      final quotes = await _db.getUserQuotes(
        searchQuery: query.isEmpty ? null : query,
        tagIds: tagIds,
        categoryId: categoryId.isEmpty ? null : categoryId,
        dateStart: dateStart.isEmpty ? null : dateStart,
        dateEnd: dateEnd.isEmpty ? null : dateEnd,
        selectedWeathers: weathers,
        selectedDayPeriods: dayPeriods,
        offset: offset,
        limit: limit,
      );

      final total = await _db.getQuotesCount(
        searchQuery: query.isEmpty ? null : query,
        tagIds: tagIds,
        categoryId: categoryId.isEmpty ? null : categoryId,
        dateStart: dateStart.isEmpty ? null : dateStart,
        dateEnd: dateEnd.isEmpty ? null : dateEnd,
        selectedWeathers: weathers,
        selectedDayPeriods: dayPeriods,
      );

      final categories = await _db.getCategories();
      final tagNameMap = <String, String>{
        for (final category in categories) category.id: category.name,
      };

      final formattedNotes = quotes.map((q) {
        final snippet = _buildMatchSnippet(q.content, query);
        final note = <String, Object?>{
          'id': q.id,
          'content_preview': _truncate(q.content, 200),
          'date': q.date,
          'content_length': q.content.length,
          'is_truncated': q.content.length > 200,
        };
        if (snippet != null) {
          note['match_snippet'] = snippet.text;
          note['match_start'] = snippet.matchStart;
          note['match_end'] = snippet.matchEnd;
        }

        // 标签：返回人类可读名称
        final tagNames = q.tagIds
            .where((id) => tagNameMap.containsKey(id))
            .map((id) => tagNameMap[id]!)
            .toList();
        if (tagNames.isNotEmpty) note['tags'] = tagNames;

        // 位置信息：优先 poiName，其次 location
        final loc = q.poiName ?? q.location;
        if (loc != null && loc.isNotEmpty) note['location'] = loc;

        // 天气 + 气温
        if (q.weather != null && q.weather!.isNotEmpty) {
          note['weather'] = q.weather;
        }
        if (q.temperature != null && q.temperature!.isNotEmpty) {
          note['temperature'] = q.temperature;
        }

        // 时段
        if (q.dayPeriod != null && q.dayPeriod!.isNotEmpty) {
          note['day_period'] = q.dayPeriod;
        }

        // 来源信息
        final src = q.source;
        if (src != null && src.isNotEmpty) note['source'] = src;

        // 喜爱度
        if (q.favoriteCount > 0) note['favorite_count'] = q.favoriteCount;

        // 分类
        if (q.categoryId != null && q.categoryId!.isNotEmpty) {
          final catName = tagNameMap[q.categoryId!];
          if (catName != null) {
            note['category'] = catName;
          }
        }

        return note;
      }).toList();

      final response = {
        'notes': formattedNotes,
        'pagination': {
          'offset': offset,
          'limit': limit,
          'next_offset': offset + formattedNotes.length,
          'has_more': total > offset + formattedNotes.length,
          'total_count': total,
        },
        'summary':
            '找到 ${formattedNotes.length} 条匹配笔记${total > offset + formattedNotes.length ? '（总计 $total 条，可分页查看）' : ''}',
      };

      return ToolResult(
        toolCallId: call.id,
        content: jsonEncode(response),
      );
    } catch (e, stack) {
      logError('ExploreNotesTool.execute 失败',
          error: e, stackTrace: stack, source: 'ExploreNotesTool');
      return ToolResult(
        toolCallId: call.id,
        content: '探索笔记时出错：$e',
        isError: true,
      );
    }
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  static _MatchSnippet? _buildMatchSnippet(String content, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return null;

    final lowerContent = content.toLowerCase();
    final matchStart = lowerContent.indexOf(normalizedQuery);
    if (matchStart < 0) return null;

    final matchEnd = matchStart + normalizedQuery.length;
    final snippetStart = (matchStart - 80).clamp(0, content.length).toInt();
    final snippetEnd = (matchEnd + 120).clamp(0, content.length).toInt();
    final prefix = snippetStart > 0 ? '...' : '';
    final suffix = snippetEnd < content.length ? '...' : '';
    return _MatchSnippet(
      text: '$prefix${content.substring(snippetStart, snippetEnd)}$suffix',
      matchStart: matchStart,
      matchEnd: matchEnd,
    );
  }
}

class _MatchSnippet {
  const _MatchSnippet({
    required this.text,
    required this.matchStart,
    required this.matchEnd,
  });

  final String text;
  final int matchStart;
  final int matchEnd;
}
