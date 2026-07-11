import 'dart:convert';

import 'package:thoughtecho/services/database_service.dart';

import '../../models/rich_text_edit.dart';
import '../../utils/quill_structured_edit.dart';
import '../agent_tool.dart';
import 'tag_argument_resolver.dart';

/// 提议创建一条新笔记，输出 Smart Result 卡片供用户直接保存或打开编辑器。
class ProposeNewNoteTool extends AgentTool {
  const ProposeNewNoteTool(this._databaseService);

  final DatabaseService _databaseService;

  @override
  String get name => 'propose_new_note';

  @override
  String get description => '【核心工具】提议新建一条笔记。适用于把 AI 生成内容整理成新笔记，'
      '并可附带现有标签，以及是否让程序附加当前位置/天气。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '建议卡片标题，例如"新笔记草稿"'},
          'content': {'type': 'string', 'description': '新笔记正文内容'},
          'blocks': {
            'type': 'array',
            'description': '可选：原生富文本块；需要格式时优先使用，不要同时提交 content',
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
          'author': {'type': 'string', 'description': '可选：作者名称'},
          'source': {'type': 'string', 'description': '可选：出处/作品名称'},
          'tag_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '可选：从 get_tags 返回的现有标签 ID 列表（优先使用）',
          },
          'tag_names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '可选兼容字段：现有标签名称列表；名称重复时会被拒绝',
          },
          'include_location': {
            'type': 'boolean',
            'description': '可选：是否建议由程序附加当前位置；不传时采用用户默认设置'
          },
          'include_weather': {
            'type': 'boolean',
            'description': '可选：是否建议由程序附加当前天气；不传时采用用户默认设置'
          },
          'reason': {'type': 'string', 'description': '可选：为什么建议创建这条笔记'},
        },
        'required': ['title'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final title = call.getString('title');
    var content = call.getString('content');
    List<RichTextBlock>? blocks;
    final rawBlocks = call.arguments['blocks'];
    if (rawBlocks is List) {
      blocks = rawBlocks
          .whereType<Map>()
          .map((item) => RichTextBlock.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .toList(growable: false);
      if (blocks.isNotEmpty) {
        content = QuillStructuredEdit.plainTextOf(
          QuillStructuredEdit.documentFromBlocks(blocks),
        );
      }
    }
    final author = call.getString('author');
    final source = call.getString('source');
    final reason = call.getString('reason');
    final includeLocation = call.arguments['include_location'];
    final includeWeather = call.arguments['include_weather'];

    if (title.isEmpty || content.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '标题和内容不能为空',
        isError: true,
        retryable: true,
      );
    }

    final resolvedTags =
        await resolveTagArguments(_databaseService, call.arguments);
    if (resolvedTags.hasError) {
      return ToolResult(
        toolCallId: call.id,
        content: resolvedTags.errorMessage!,
        isError: true,
        retryable: true,
      );
    }

    final payload = <String, Object?>{
      'type': 'smart_result',
      'title': title,
      'content': content,
      'action': 'create',
      if (blocks?.isNotEmpty == true)
        'rich_document': blocks!.map((block) => block.toJson()).toList(),
      'tag_ids': resolvedTags.ids,
      'tag_names': resolvedTags.names,
    };
    if (includeLocation is bool) {
      payload['include_location'] = includeLocation;
    }
    if (includeWeather is bool) {
      payload['include_weather'] = includeWeather;
    }
    if (author.isNotEmpty) {
      payload['author'] = author;
    }
    if (source.isNotEmpty) {
      payload['source'] = source;
    }
    if (reason.isNotEmpty) {
      payload['reason'] = reason;
    }

    return ToolResult(
      toolCallId: call.id,
      content: '```smart_result\n${jsonEncode(payload)}\n```',
    );
  }
}
