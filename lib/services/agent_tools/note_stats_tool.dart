import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import '../database_service.dart';

/// 获取用户笔记的统计概览
class NoteStatsTool extends AgentTool {
  final DatabaseService _db;
  const NoteStatsTool(this._db);

  @override
  String get name => 'get_note_stats';

  @override
  String get description => '获取用户笔记的统计概览（总数、日期范围、分类分布、情感分布等）';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'start_date': {
            'type': 'string',
            'description': '起始日期（ISO 格式，可选）',
          },
          'end_date': {
            'type': 'string',
            'description': '结束日期（ISO 格式，可选）',
          },
        },
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final startDate = call.arguments['start_date'] as String?;
    final endDate = call.arguments['end_date'] as String?;

    try {
      final db = _db.database;

      // 构建 WHERE 子句
      String? where;
      List<Object?>? whereArgs;
      if (startDate != null || endDate != null) {
        final conditions = <String>[];
        whereArgs = <Object?>[];
        if (startDate != null) {
          conditions.add('date >= ?');
          whereArgs.add(startDate);
        }
        if (endDate != null) {
          conditions.add('date <= ?');
          whereArgs.add(endDate);
        }
        where = conditions.join(' AND ');
      }

      // 总数
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as c FROM quotes${where != null ? ' WHERE $where' : ''}',
        whereArgs,
      );
      final total = countResult.first['c'] as int? ?? 0;

      // 日期范围
      final rangeResult = await db.rawQuery(
        'SELECT MIN(date) as earliest, MAX(date) as latest FROM quotes${where != null ? ' WHERE $where' : ''}',
        whereArgs,
      );
      final earliest = rangeResult.first['earliest']?.toString() ?? '无';
      final latest = rangeResult.first['latest']?.toString() ?? '无';

      // 情感分布
      final sentimentResult = await db.rawQuery(
        'SELECT sentiment, COUNT(*) as c FROM quotes${where != null ? ' WHERE $where AND' : ' WHERE'} sentiment IS NOT NULL GROUP BY sentiment ORDER BY c DESC',
        whereArgs,
      );
      final sentimentLines = sentimentResult
          .map((r) => '  ${r['sentiment']}: ${r['c']}')
          .join('\n');

      // 有位置的笔记数
      final locResult = await db.rawQuery(
        'SELECT COUNT(*) as c FROM quotes${where != null ? ' WHERE $where AND' : ' WHERE'} (latitude IS NOT NULL AND longitude IS NOT NULL)',
        whereArgs,
      );
      final withLocation = locResult.first['c'] as int? ?? 0;

      // 有 AI 分析的笔记数
      final aiResult = await db.rawQuery(
        'SELECT COUNT(*) as c FROM quotes${where != null ? ' WHERE $where AND' : ' WHERE'} ai_analysis IS NOT NULL AND ai_analysis != \'\'',
        whereArgs,
      );
      final withAI = aiResult.first['c'] as int? ?? 0;

      final buffer = StringBuffer()
        ..writeln('📊 笔记统计概览')
        ..writeln('─────────────────')
        ..writeln('总数: $total 条')
        ..writeln('日期范围: $earliest ~ $latest')
        ..writeln('有位置信息: $withLocation 条')
        ..writeln('有 AI 分析: $withAI 条');

      if (sentimentLines.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('情感分布:')
          ..writeln(sentimentLines);
      }

      return ToolResult(toolCallId: call.id, content: buffer.toString());
    } catch (e, stack) {
      logError('NoteStatsTool.execute 失败', error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '获取统计信息时出错：$e',
        isError: true,
      );
    }
  }
}
