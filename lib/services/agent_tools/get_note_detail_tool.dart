import 'dart:convert';

import '../../utils/app_logger.dart';
import '../../utils/agent_note_document_codec.dart';
import '../agent_tool.dart';
import '../database_service.dart';
import 'propose_note_edit_tool.dart';

/// 获取单篇笔记详情工具 - 允许 AI 获取笔记的完整正文和元数据
class GetNoteDetailTool extends AgentTool {
  final DatabaseService _db;

  const GetNoteDetailTool(this._db);

  @override
  String get name => 'get_note_detail';

  @override
  String get description =>
      '【只读】获取指定笔记的完整详细内容，包括标题、作者、出处、分类、标签等元数据和完整正文。当你想润色或深入整理某篇特定笔记时调用。';

  @override
  bool get isReadOnly => true;

  @override
  bool get isConcurrencySafe => true;

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'string', 'description': '要获取详情的笔记 ID'},
        },
        'required': ['note_id'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final noteId = call.getString('note_id').trim();

    if (noteId.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'note_id不能为空',
        isError: true,
      );
    }

    try {
      final q = await _db.getQuoteById(noteId);
      if (q == null) {
        return ToolResult(
          toolCallId: call.id,
          content: '未找到ID为$noteId的笔记',
          isError: true,
        );
      }

      // 批量收集所有需要查询的分类ID和标签ID
      final idsToFetch = <String>{
        if (q.categoryId != null && q.categoryId!.isNotEmpty) q.categoryId!,
        ...q.tagIds,
      };

      final nameMap = <String, String>{};
      for (final id in idsToFetch) {
        final cat = await _db.getCategoryById(id);
        if (cat != null) {
          nameMap[id] = cat.name;
        }
      }

      final response = <String, Object?>{
        'id': q.id,
        'content': q.content,
        'date': q.date,
        'content_length': q.content.length,
        'document_kind': ProposeNoteEditTool.kindForQuote(q).name,
        'document_revision': ProposeNoteEditTool.revisionForQuote(q),
      };
      if (ProposeNoteEditTool.kindForQuote(q).name == 'rich') {
        response['document_ops'] = AgentNoteDocumentCodec.sanitizeForModel(
          ProposeNoteEditTool.opsForQuote(q),
        );
      }

      // 优先使用 poiName，其次使用 location
      final loc =
          (q.poiName != null && q.poiName!.isNotEmpty) ? q.poiName : q.location;
      if (loc != null && loc.isNotEmpty) {
        response['location'] = loc;
      }

      if (q.weather != null && q.weather!.isNotEmpty) {
        response['weather'] = q.weather;
      }
      if (q.temperature != null && q.temperature!.isNotEmpty) {
        response['temperature'] = q.temperature;
      }

      if (q.sourceAuthor != null && q.sourceAuthor!.isNotEmpty) {
        response['author'] = q.sourceAuthor;
      }
      if (q.sourceWork != null && q.sourceWork!.isNotEmpty) {
        response['source'] = q.sourceWork;
      }

      if (q.favoriteCount > 0) {
        response['favorite_count'] = q.favoriteCount;
      }

      if (q.categoryId != null && q.categoryId!.isNotEmpty) {
        final catName = nameMap[q.categoryId!];
        if (catName != null) {
          response['category'] = catName;
        }
      }

      final tagNames =
          q.tagIds.map((id) => nameMap[id]).whereType<String>().toList();
      if (tagNames.isNotEmpty) {
        response['tags'] = tagNames;
      }

      return ToolResult(toolCallId: call.id, content: jsonEncode(response));
    } catch (e, stack) {
      logError(
        'GetNoteDetailTool.execute 失败',
        error: e,
        stackTrace: stack,
        source: 'GetNoteDetailTool',
      );
      return ToolResult(
        toolCallId: call.id,
        content: '读取笔记详情失败：$e',
        isError: true,
      );
    }
  }
}
