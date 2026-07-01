import 'dart:convert';

import 'package:thoughtecho/services/database_service.dart';

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
          'author': {'type': 'string', 'description': '可选：作者名称'},
          'source': {'type': 'string', 'description': '可选：出处/作品名称'},
          'tag_names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '可选：从应用现有标签中选择的标签名称列表',
          },
          'include_location': {
            'type': 'boolean',
            'description': '是否建议由程序附加当前位置'
          },
          'include_weather': {
            'type': 'boolean',
            'description': '是否建议由程序附加当前天气'
          },
          'reason': {'type': 'string', 'description': '可选：为什么建议创建这条笔记'},
        },
        'required': ['title', 'content'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final title = call.getString('title');
    final content = call.getString('content');
    final author = call.getString('author');
    final source = call.getString('source');
    final reason = call.getString('reason');
    final includeLocation = call.arguments['include_location'] == true;
    final includeWeather = call.arguments['include_weather'] == true;

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
      'tag_ids': resolvedTags.ids,
      'tag_names': resolvedTags.names,
      'include_location': includeLocation,
      'include_weather': includeWeather,
    };
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
