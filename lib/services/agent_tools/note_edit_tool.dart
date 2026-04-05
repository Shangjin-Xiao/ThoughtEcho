import 'dart:convert';

import '../../utils/app_logger.dart';
import '../../models/quote_model.dart';
import '../agent_tool.dart';
import '../database_service.dart';

/// 编辑指定笔记的内容（如续写、润色结果的应用）
///
/// 注意：Agent 编辑只处理纯文本内容。为保持 content 与 deltaContent 同步：
/// - replace 模式：清空 deltaContent，用户下次在全屏编辑器打开时会从纯文本重建
/// - append 模式：尝试将新内容追加到现有 Delta JSON，若失败则清空 deltaContent
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
      final existingQuote = await _db.getQuoteById(noteId);
      if (existingQuote == null) {
        return ToolResult(
          toolCallId: call.id,
          content: '未找到 ID 为 $noteId 的笔记',
          isError: true,
        );
      }

      final existing = existingQuote.content;
      final String finalContent;
      final String? finalDeltaContent;

      if (mode == 'append') {
        // 追加模式：尝试将新内容追加到现有 Delta JSON
        finalContent = '$existing\n\n$newContent';
        finalDeltaContent =
            _appendToDelta(existingQuote.deltaContent, newContent);
      } else {
        // 替换模式：清空 deltaContent，从纯文本重建
        // 用户下次在全屏编辑器打开时会自动从 content 生成新的 Delta
        finalContent = newContent;
        finalDeltaContent = _createPlainTextDelta(newContent);
      }

      final updatedQuote = Quote(
        id: existingQuote.id,
        content: finalContent,
        date: existingQuote.date,
        source: existingQuote.source,
        sourceAuthor: existingQuote.sourceAuthor,
        sourceWork: existingQuote.sourceWork,
        tagIds: existingQuote.tagIds,
        aiAnalysis: existingQuote.aiAnalysis,
        sentiment: existingQuote.sentiment,
        keywords: existingQuote.keywords,
        summary: existingQuote.summary,
        categoryId: existingQuote.categoryId,
        colorHex: existingQuote.colorHex,
        location: existingQuote.location,
        latitude: existingQuote.latitude,
        longitude: existingQuote.longitude,
        poiName: existingQuote.poiName,
        weather: existingQuote.weather,
        temperature: existingQuote.temperature,
        editSource: null,
        deltaContent: finalDeltaContent,
        dayPeriod: existingQuote.dayPeriod,
        lastModified: DateTime.now().toIso8601String(),
        favoriteCount: existingQuote.favoriteCount,
      );
      await _db.updateQuote(updatedQuote);

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

  /// 将新内容追加到现有 Delta JSON
  ///
  /// Delta JSON 格式为 [{"insert": "text"}, {"insert": "\n"}]
  /// 追加时在末尾添加两个换行符和新内容
  String? _appendToDelta(String? existingDelta, String newContent) {
    if (existingDelta == null || existingDelta.isEmpty) {
      // 没有现有 Delta，创建新的纯文本 Delta
      return _createPlainTextDelta(newContent);
    }

    try {
      final List<dynamic> ops = jsonDecode(existingDelta) as List<dynamic>;
      if (ops.isEmpty) {
        return _createPlainTextDelta(newContent);
      }

      // 追加：两个换行符 + 新内容
      ops.add({'insert': '\n\n$newContent'});

      return jsonEncode(ops);
    } catch (e) {
      // Delta JSON 解析失败，回退到创建新的纯文本 Delta
      logWarning('_appendToDelta: Delta JSON 解析失败 ($e)，回退到纯文本',
          source: 'NoteEditTool');
      return null; // 返回 null 让编辑器从 content 重建
    }
  }

  /// 从纯文本创建 Delta JSON
  ///
  /// 创建最简单的 Delta 格式：[{"insert": "text\n"}]
  String _createPlainTextDelta(String content) {
    // Quill Delta 要求文本以换行符结尾
    final normalizedContent = content.endsWith('\n') ? content : '$content\n';
    final ops = [
      {'insert': normalizedContent}
    ];
    return jsonEncode(ops);
  }
}
