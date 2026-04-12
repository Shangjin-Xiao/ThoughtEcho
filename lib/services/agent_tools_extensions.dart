import 'dart:convert';

import '../services/agent_tool.dart';
import '../services/chat_session_service.dart';
import '../utils/app_logger.dart';

/// 获取最近笔记工具
class GetRecentNotesTool extends AgentTool {
  final ChatSessionService _chatSessionService;

  const GetRecentNotesTool(this._chatSessionService);

  @override
  String get name => 'get_recent_notes';

  @override
  String get description => '【只读】获取最近创建的笔记。此工具无法修改笔记。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': '返回的笔记数量（1-20），默认10',
            'minimum': 1,
            'maximum': 20,
          },
        },
        'required': [],
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    try {
      final limit = toolCall.getInt('limit', defaultValue: 10);
      final notes = await _chatSessionService.getRecentNotes(limit: limit);

      if (notes.isEmpty) {
        return ToolResult(
          toolCallId: toolCall.id,
          content: '暂无笔记',
        );
      }

      final formatted = notes.asMap().entries.map((e) {
        final note = e.value;
        return {
          'index': e.key + 1,
          'id': note['id'],
          'title': _extractTitle(note['content'] ?? ''),
          'preview': _extractPreview(note['content'] ?? ''),
          'date': note['date'],
          'tags': note['tags'] ?? [],
        };
      }).toList();

      return ToolResult(
        toolCallId: toolCall.id,
        content: jsonEncode({
          'count': formatted.length,
          'notes': formatted,
        }),
      );
    } catch (e, stack) {
      toolCall.logError(
        'get_recent_notes 工具执行失败',
        error: e,
        stackTrace: stack,
      );
      return ToolResult(
        toolCallId: toolCall.id,
        content: '获取笔记失败: ${e.toString()}',
        isError: true,
      );
    }
  }

  static String _extractTitle(String content) {
    if (content.isEmpty) return '(空)';
    final lines = content.split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.length > 50) {
      return '${firstLine.substring(0, 50)}...';
    }
    return firstLine;
  }

  static String _extractPreview(String content) {
    if (content.isEmpty) return '';
    final preview = content.replaceAll('\n', ' ').trim();
    if (preview.length > 100) {
      return '${preview.substring(0, 100)}...';
    }
    return preview;
  }
}

/// 按标签查询笔记工具
class GetNotesByTagsTool extends AgentTool {
  final ChatSessionService _chatSessionService;

  const GetNotesByTagsTool(this._chatSessionService);

  @override
  String get name => 'get_notes_by_tags';

  @override
  String get description => '【只读】按标签查询笔记。此工具无法修改笔记。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标签ID列表，会返回包含所有这些标签的笔记',
            'minItems': 1,
          },
          'limit': {
            'type': 'integer',
            'description': '返回的笔记数量（1-20），默认10',
            'minimum': 1,
            'maximum': 20,
          },
        },
        'required': ['tags'],
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    try {
      final tagsArg = toolCall.arguments['tags'];
      if (tagsArg is! List || tagsArg.isEmpty) {
        return ToolResult(
          toolCallId: toolCall.id,
          content: '标签列表不能为空',
          isError: true,
        );
      }

      final tags = tagsArg.map((t) => t.toString()).toList();
      final limit = toolCall.getInt('limit', defaultValue: 10);
      final notes = await _chatSessionService.getNotesByTags(tags, limit: limit);

      if (notes.isEmpty) {
        return ToolResult(
          toolCallId: toolCall.id,
          content: '没有找到匹配标签的笔记',
        );
      }

      final formatted = notes.asMap().entries.map((e) {
        final note = e.value;
        return {
          'index': e.key + 1,
          'id': note['id'],
          'title': _extractTitle(note['content'] ?? ''),
          'preview': _extractPreview(note['content'] ?? ''),
          'date': note['date'],
        };
      }).toList();

      return ToolResult(
        toolCallId: toolCall.id,
        content: jsonEncode({
          'query_tags': tags,
          'count': formatted.length,
          'notes': formatted,
        }),
      );
    } catch (e, stack) {
      toolCall.logError(
        'get_notes_by_tags 工具执行失败',
        error: e,
        stackTrace: stack,
      );
      return ToolResult(
        toolCallId: toolCall.id,
        content: '查询笔记失败: ${e.toString()}',
        isError: true,
      );
    }
  }

  static String _extractTitle(String content) {
    if (content.isEmpty) return '(空)';
    final lines = content.split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.length > 50) {
      return '${firstLine.substring(0, 50)}...';
    }
    return firstLine;
  }

  static String _extractPreview(String content) {
    if (content.isEmpty) return '';
    final preview = content.replaceAll('\n', ' ').trim();
    if (preview.length > 100) {
      return '${preview.substring(0, 100)}...';
    }
    return preview;
  }
}

/// 按日期范围查询笔记工具
class GetNotesByDateRangeTool extends AgentTool {
  final ChatSessionService _chatSessionService;

  const GetNotesByDateRangeTool(this._chatSessionService);

  @override
  String get name => 'get_notes_by_date_range';

  @override
  String get description => '【只读】查询指定日期范围内的笔记。此工具无法修改笔记。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'date_start': {
            'type': 'string',
            'description': '开始日期（ISO8601格式，例如2024-01-01）',
          },
          'date_end': {
            'type': 'string',
            'description': '结束日期（ISO8601格式，例如2024-12-31）',
          },
          'limit': {
            'type': 'integer',
            'description': '返回的笔记数量（1-30），默认20',
            'minimum': 1,
            'maximum': 30,
          },
        },
        'required': ['date_start', 'date_end'],
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    try {
      final dateStartStr = toolCall.arguments['date_start']?.toString();
      final dateEndStr = toolCall.arguments['date_end']?.toString();

      if (dateStartStr == null ||
          dateStartStr.isEmpty ||
          dateEndStr == null ||
          dateEndStr.isEmpty) {
        return ToolResult(
          toolCallId: toolCall.id,
          content: '日期参数不能为空',
          isError: true,
        );
      }

      try {
        final dateStart = DateTime.parse(dateStartStr);
        final dateEnd = DateTime.parse(dateEndStr);
        final limit = toolCall.getInt('limit', defaultValue: 20);

        final notes = await _chatSessionService.getNotesByDateRange(
          dateStart,
          dateEnd,
          limit: limit,
        );

        if (notes.isEmpty) {
          return ToolResult(
            toolCallId: toolCall.id,
            content: '指定日期范围内没有笔记',
          );
        }

        final formatted = notes.asMap().entries.map((e) {
          final note = e.value;
          return {
            'index': e.key + 1,
            'id': note['id'],
            'title': _extractTitle(note['content'] ?? ''),
            'preview': _extractPreview(note['content'] ?? ''),
            'date': note['date'],
          };
        }).toList();

        return ToolResult(
          toolCallId: toolCall.id,
          content: jsonEncode({
            'date_range': {
              'start': dateStartStr,
              'end': dateEndStr,
            },
            'count': formatted.length,
            'notes': formatted,
          }),
        );
      } on FormatException {
        return ToolResult(
          toolCallId: toolCall.id,
          content: '日期格式无效，请使用ISO8601格式 （例如2024-01-01）',
          isError: true,
        );
      }
      } catch (e, stack) {
      toolCall.logError(
        'get_notes_by_date_range 工具执行失败',
        error: e,
        stackTrace: stack,
      );
      return ToolResult(
        toolCallId: toolCall.id,
        content: '查询笔记失败: ${e.toString()}',
        isError: true,
      );
      }
  }

  static String _extractTitle(String content) {
    if (content.isEmpty) return '(空)';
    final lines = content.split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.length > 50) {
      return '${firstLine.substring(0, 50)}...';
    }
    return firstLine;
  }

  static String _extractPreview(String content) {
    if (content.isEmpty) return '';
    final preview = content.replaceAll('\n', ' ').trim();
    if (preview.length > 100) {
      return '${preview.substring(0, 100)}...';
    }
    return preview;
  }
}
