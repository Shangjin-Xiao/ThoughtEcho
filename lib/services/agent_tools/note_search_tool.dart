import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import '../database_service.dart';

/// 搜索用户笔记内容
class NoteSearchTool extends AgentTool {
  static const int _defaultLimit = 10;
  static const int _maxLimit = 20;

  final DatabaseService _db;
  const NoteSearchTool(this._db);

  @override
  String get name => 'search_notes';

  @override
  String get description => '搜索用户笔记，根据关键词匹配笔记内容，返回匹配笔记的摘要';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词',
          },
          'limit': {
            'type': 'integer',
            'description': '最大返回数量（默认 10）',
          },
        },
        'required': ['query'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final query = call.arguments['query'] as String? ?? '';
    final requestedLimit =
        (call.arguments['limit'] as num?)?.toInt() ?? _defaultLimit;
    final limit = requestedLimit.clamp(1, _maxLimit).toInt();

    if (query.trim().isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '搜索关键词不能为空',
        isError: true,
      );
    }

    try {
      final db = _db.database;

      final rows = await db.query(
        'quotes',
        columns: ['id', 'content', 'date', 'location', 'poi_name'],
        where: 'content LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'date DESC',
        limit: limit,
      );

      if (rows.isEmpty) {
        return ToolResult(
          toolCallId: call.id,
          content: '未找到包含「$query」的笔记。',
        );
      }

      final buffer = StringBuffer('找到 ${rows.length} 条笔记：\n\n');
      for (final row in rows) {
        final content = row['content'] as String? ?? '';
        final preview =
            content.length > 200 ? '${content.substring(0, 200)}…' : content;
        final date = row['date'] as String? ?? '未知日期';
        final location =
            row['poi_name'] as String? ?? row['location'] as String? ?? '';
        buffer.writeln('- [$date] $preview');
        if (location.isNotEmpty) buffer.writeln('  📍 $location');
        buffer.writeln();
      }

      return ToolResult(toolCallId: call.id, content: buffer.toString());
    } catch (e, stack) {
      logError('NoteSearchTool.execute 失败', error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '搜索笔记时出错：$e',
        isError: true,
      );
    }
  }
}
