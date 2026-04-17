import 'dart:io';

import 'package:ddgs/ddgs.dart';

import '../../utils/app_logger.dart';
import '../agent_tool.dart';

/// 搜索互联网获取实时信息（使用 ddgs 库）
class WebSearchTool extends AgentTool {
  static const int _defaultLimit = 5;
  static const int _maxLimit = 10;

  const WebSearchTool();

  @override
  String get name => 'web_search';

  @override
  String get description => '【只读】通过外部搜索引擎搜索实时信息。此工具仅用于获取信息。';

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
            'description': '最大返回结果数（默认 5）',
          },
        },
        'required': ['query'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final query = call.getString('query');
    final requestedLimit = call.getInt('limit', defaultValue: _defaultLimit);
    final limit = requestedLimit.clamp(1, _maxLimit);

    if (query.trim().isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '搜索关键词不能为空',
        isError: true,
      );
    }

    try {
      final isChinese =
          Platform.localeName.toLowerCase().startsWith('zh') ||
              _containsChinese(query);

      // 中文查询优先使用 bing（中文搜索质量更高），否则使用 auto（多引擎）
      final backend = isChinese ? 'bing' : 'auto';
      final region = isChinese ? 'cn-zh' : 'us-en';

      logDebug('WebSearchTool: 使用 $backend ($region) 搜索 "$query"');

      final ddgs = DDGS(timeout: const Duration(seconds: 15));
      try {
        final results = await ddgs.text(
          query,
          backend: backend,
          region: region,
          maxResults: limit,
        );

        if (results.isEmpty) {
          return ToolResult(
            toolCallId: call.id,
            content: '未找到与「$query」相关的搜索结果。',
          );
        }

        final buffer = StringBuffer('搜索「$query」的结果：\n\n');
        for (var i = 0; i < results.length; i++) {
          final result = results[i];
          final title = result['title']?.toString() ?? '无标题';
          final snippet = result['body']?.toString() ??
              result['description']?.toString() ??
              '';
          final href = result['href']?.toString() ?? '';

          buffer.writeln('${i + 1}. $title');
          if (href.isNotEmpty) {
            buffer.writeln('   链接: $href');
          }
          if (snippet.isNotEmpty) {
            buffer.writeln('   摘要: $snippet');
          }
          buffer.writeln();
        }

        return ToolResult(toolCallId: call.id, content: buffer.toString());
      } finally {
        ddgs.close();
      }
    } catch (e, stack) {
      call.logError('WebSearchTool.execute 失败', error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '网络搜索时出错：$e',
        isError: true,
      );
    }
  }

  /// 检查字符串是否包含中文字符
  static bool _containsChinese(String text) {
    return RegExp(r'[\u4e00-\u9fa5]').hasMatch(text);
  }
}

