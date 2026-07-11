import 'dart:convert';

import '../../models/quote_model.dart';
import '../../models/rich_text_edit.dart';
import '../../utils/app_logger.dart';
import '../../utils/quill_delta_builder.dart';
import '../../utils/quill_structured_edit.dart';
import '../agent_tool.dart';
import '../database_service.dart';

/// Proposes precise, revision-checked edits to an existing Quill document.
class ProposeRichEditTool extends AgentTool {
  const ProposeRichEditTool(this._databaseService);

  final DatabaseService _databaseService;

  @override
  String get name => 'propose_rich_edit';

  @override
  String get description =>
      '精确修改已有富文本笔记。使用 get_note_detail 返回的 document_revision，'
      '通过唯一 old_text/anchor_text 定位，只修改指定内容并保留其余格式和媒体。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '建议卡片标题'},
          'note_id': {'type': 'string', 'description': '已有笔记 ID'},
          'base_revision': {
            'type': 'string',
            'description': 'get_note_detail 返回的 document_revision',
          },
          'operations': {
            'type': 'array',
            'minItems': 1,
            'items': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'enum': [
                    'replace',
                    'insertBefore',
                    'insertAfter',
                    'append',
                    'delete',
                  ],
                },
                'old_text': {'type': 'string'},
                'anchor_text': {'type': 'string'},
                'blocks': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'type': {
                        'type': 'string',
                        'enum': [
                          'paragraph',
                          'heading',
                          'bullet',
                          'ordered',
                          'quote',
                          'code',
                        ],
                      },
                      'level': {'type': 'integer', 'minimum': 1, 'maximum': 6},
                      'children': {
                        'type': 'array',
                        'items': {
                          'type': 'object',
                          'properties': {
                            'text': {'type': 'string'},
                            'bold': {'type': 'boolean'},
                            'italic': {'type': 'boolean'},
                            'underline': {'type': 'boolean'},
                            'strike': {'type': 'boolean'},
                            'code': {'type': 'boolean'},
                            'link': {'type': 'string'},
                          },
                          'required': ['text'],
                        },
                      },
                    },
                    'required': ['type', 'children'],
                  },
                },
              },
              'required': ['type'],
            },
          },
          'reason': {'type': 'string', 'description': '简短修改理由'},
        },
        'required': ['title', 'note_id', 'base_revision', 'operations'],
      };

  static List<Map<String, dynamic>> opsForQuote(Quote quote) =>
      DeltaBuilder.deltaFromJson(quote.deltaContent) ??
      [
        {
          'insert': quote.content.endsWith('\n')
              ? quote.content
              : '${quote.content}\n',
        },
      ];

  static String revisionForQuote(Quote quote) =>
      QuillStructuredEdit.revisionOf(opsForQuote(quote));

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final title = call.getString('title').trim();
    final noteId = call.getString('note_id').trim();
    if (title.isEmpty || noteId.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'title 和 note_id 不能为空。',
        isError: true,
        retryable: true,
      );
    }

    try {
      final quote = await _databaseService.getQuoteById(noteId);
      if (quote == null) {
        return ToolResult(
          toolCallId: call.id,
          content: '未找到 ID 为 $noteId 的笔记。',
          isError: true,
          retryable: true,
        );
      }
      final request = RichTextEditRequest.fromJson(call.arguments);
      final result = QuillStructuredEdit.apply(
        originalOps: opsForQuote(quote),
        request: request,
      );
      final preview = result.preview
          .map((item) => item.oldText.isEmpty
              ? '新增：${item.newText.trim()}'
              : '原文：${item.oldText}\n改为：${item.newText.trim()}')
          .join('\n\n');
      final payload = <String, Object?>{
        'type': 'smart_result',
        'title': title,
        'content': preview,
        'action': 'rich_edit',
        'note_id': noteId,
        'rich_edit': request.toJson(),
        if (call.getString('reason').trim().isNotEmpty)
          'reason': call.getString('reason').trim(),
      };
      return ToolResult(
        toolCallId: call.id,
        content: '```smart_result\n${jsonEncode(payload)}\n```',
      );
    } on RichTextEditConflict catch (error) {
      return ToolResult(
        toolCallId: call.id,
        content: error.message,
        isError: true,
        retryable: true,
      );
    } on RichTextEditMatchFailure catch (error) {
      return ToolResult(
        toolCallId: call.id,
        content: error.toString(),
        isError: true,
        retryable: true,
      );
    } on FormatException catch (error) {
      return ToolResult(
        toolCallId: call.id,
        content: error.message,
        isError: true,
        retryable: true,
      );
    } catch (error, stack) {
      logError(
        'ProposeRichEditTool.execute 失败',
        error: error,
        stackTrace: stack,
        source: 'ProposeRichEditTool',
      );
      return ToolResult(
        toolCallId: call.id,
        content: '生成精确编辑建议失败。',
        isError: true,
      );
    }
  }
}
