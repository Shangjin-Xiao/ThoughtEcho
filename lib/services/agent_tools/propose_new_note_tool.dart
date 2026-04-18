import 'dart:convert';

import 'package:thoughtecho/services/database_service.dart';

import '../agent_tool.dart';

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
          'title': {
            'type': 'string',
            'description': '建议卡片标题，例如“新笔记草稿”',
          },
          'content': {
            'type': 'string',
            'description': '新笔记正文内容',
          },
          'tag_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '可选：从应用现有标签中选择的标签 ID 列表',
          },
          'include_location': {
            'type': 'boolean',
            'description': '是否建议由程序附加当前位置',
          },
          'include_weather': {
            'type': 'boolean',
            'description': '是否建议由程序附加当前天气',
          },
          'reason': {
            'type': 'string',
            'description': '可选：为什么建议创建这条笔记',
          },
        },
        'required': ['title', 'content'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final title = call.getString('title');
    final content = call.getString('content');
    final reason = call.getString('reason');
    final includeLocation = call.arguments['include_location'] == true;
    final includeWeather = call.arguments['include_weather'] == true;

    if (title.isEmpty || content.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '标题和内容不能为空',
        isError: true,
      );
    }

    final rawTagIds = call.arguments['tag_ids'];
    final tagIds = rawTagIds is List
        ? rawTagIds
            .map((item) => item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toList()
        : <String>[];

    final knownTags = await _databaseService.getCategories();
    final visibleTags =
        knownTags.where((tag) => tag.id != 'system_hidden_tag').toList();
    final validTagIds = visibleTags.map((tag) => tag.id).toSet();
    final invalidTagIds =
        tagIds.where((tagId) => !validTagIds.contains(tagId)).toList();
    if (invalidTagIds.isNotEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '存在无效标签 ID：${invalidTagIds.join(', ')}',
        isError: true,
      );
    }

    final payload = <String, Object?>{
      'type': 'smart_result',
      'title': title,
      'content': content,
      'action': 'create',
      'tag_ids': tagIds,
      'include_location': includeLocation,
      'include_weather': includeWeather,
    };
    if (reason.isNotEmpty) {
      payload['reason'] = reason;
    }

    return ToolResult(
      toolCallId: call.id,
      content: '```smart_result\n${jsonEncode(payload)}\n```',
    );
  }
}
