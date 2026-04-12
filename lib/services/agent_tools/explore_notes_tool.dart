import 'dart:convert';
import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import '../database_service.dart';

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
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词（可选）',
          },
          'tag_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标签ID列表（可选）',
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
      final tagIds = (call.arguments['tag_ids'] as List?)
          ?.whereType<String>()
          .toList();
      final categoryId = call.getString('category_id');
      final dateStart = call.getString('date_start');
      final dateEnd = call.getString('date_end');
      final weathers = (call.arguments['weathers'] as List?)
          ?.whereType<String>()
          .toList();
      final dayPeriods = (call.arguments['day_periods'] as List?)
          ?.whereType<String>()
          .toList();
      final offset = call.getInt('offset', defaultValue: 0);
      final limit = call.getInt('limit', defaultValue: 10).clamp(1, 20);

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

      final formattedNotes = quotes.map((q) => {
        'id': q.id,
        'content_preview': q.content.length > 200 ? '${q.content.substring(0, 200)}...' : q.content,
        'date': q.date,
        'tags': q.tagIds,
        'weather': q.weather,
        'day_period': q.dayPeriod,
        'content_length': q.content.length,
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
        'summary': '找到 ${formattedNotes.length} 条匹配笔记' + (total > formattedNotes.length ? '（总计 $total 条，可分页查看）' : ''),
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
}
