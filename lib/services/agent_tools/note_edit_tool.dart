import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import '../database_service.dart';

/// 编辑指定笔记的内容（如续写、润色结果的应用）
class NoteEditTool extends AgentTool {
  final DatabaseService _db;
  const NoteEditTool(this._db);

  @override
  String get name => 'edit_note';

  @override
  String get description => '编辑指定笔记的内容，支持替换或追加模式';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'note_id': {
            'type': 'string',
            'description': '要编辑的笔记 ID',
          },
          'new_content': {
            'type': 'string',
            'description': '新的笔记内容',
          },
          'mode': {
            'type': 'string',
            'enum': ['replace', 'append'],
            'description': '编辑模式：replace（替换）或 append（追加），默认 replace',
          },
        },
        'required': ['note_id', 'new_content'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final noteId = call.arguments['note_id'] as String? ?? '';
    final newContent = call.arguments['new_content'] as String? ?? '';
    final mode = call.arguments['mode'] as String? ?? 'replace';

    if (noteId.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '笔记 ID 不能为空',
        isError: true,
      );
    }
    if (newContent.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '新内容不能为空',
        isError: true,
      );
    }

    try {
      final db = _db.database;

      // 读取现有笔记
      final rows = await db.query(
        'quotes',
        where: 'id = ?',
        whereArgs: [noteId],
        limit: 1,
      );

      if (rows.isEmpty) {
        return ToolResult(
          toolCallId: call.id,
          content: '未找到 ID 为 $noteId 的笔记',
          isError: true,
        );
      }

      final existing = rows.first['content'] as String? ?? '';
      final finalContent = switch (mode) {
        'append' => '$existing\n\n$newContent',
        _ => newContent,
      };

      await db.update(
        'quotes',
        {
          'content': finalContent,
          'last_modified': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [noteId],
      );

      final preview = finalContent.length > 100
          ? '${finalContent.substring(0, 100)}…'
          : finalContent;

      return ToolResult(
        toolCallId: call.id,
        content: '✅ 笔记已${mode == 'append' ? '追加' : '更新'}：$preview',
      );
    } catch (e, stack) {
      logError('NoteEditTool.execute 失败', error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '编辑笔记时出错：$e',
        isError: true,
      );
    }
  }
}
