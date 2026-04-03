import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import '../agent_tool.dart';

/// 搜索互联网获取实时信息（Bing HTTP 抓取，免费无 Key）
class WebSearchTool extends AgentTool {
  static const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  const WebSearchTool();

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索互联网获取实时信息（使用 Bing 搜索）';

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
    final query = call.arguments['query'] as String? ?? '';
    final limit = (call.arguments['limit'] as num?)?.toInt() ?? 5;

    if (query.trim().isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '搜索关键词不能为空',
        isError: true,
      );
    }

    try {
      final encoded = Uri.encodeComponent(query);
      final url =
          Uri.parse('https://cn.bing.com/search?q=$encoded&count=$limit');

      final response = await http.get(url, headers: {
        'User-Agent': _userAgent
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return ToolResult(
          toolCallId: call.id,
          content: '搜索请求失败（HTTP ${response.statusCode}）',
          isError: true,
        );
      }

      final results = _parseResults(response.body, limit);

      if (results.isEmpty) {
        return ToolResult(
          toolCallId: call.id,
          content: '未找到与「$query」相关的搜索结果。',
        );
      }

      final buffer = StringBuffer('🔍 搜索「$query」的结果：\n\n');
      for (var i = 0; i < results.length; i++) {
        buffer.writeln('${i + 1}. ${results[i].title}');
        if (results[i].snippet.isNotEmpty) {
          buffer.writeln('   ${results[i].snippet}');
        }
        buffer.writeln();
      }

      return ToolResult(toolCallId: call.id, content: buffer.toString());
    } catch (e, stack) {
      logError('WebSearchTool.execute 失败', error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '网络搜索时出错：$e',
        isError: true,
      );
    }
  }

  /// 从 Bing HTML 中提取搜索结果
  List<_SearchResult> _parseResults(String html, int limit) {
    final results = <_SearchResult>[];

    // 匹配 Bing 搜索结果块：<li class="b_algo">...<h2><a ...>title</a></h2>...<p>snippet</p>
    final blockPattern = RegExp(
      r'<li[^>]*class="b_algo"[^>]*>(.*?)</li>',
      dotAll: true,
    );

    for (final block in blockPattern.allMatches(html)) {
      if (results.length >= limit) break;

      final blockHtml = block.group(1) ?? '';

      // 提取标题
      final titleMatch = RegExp(
        r'<h2[^>]*>.*?<a[^>]*>(.*?)</a>',
        dotAll: true,
      ).firstMatch(blockHtml);
      final title = _stripHtml(titleMatch?.group(1) ?? '').trim();

      // 提取摘要
      final snippetMatch = RegExp(
        r'<p[^>]*>(.*?)</p>',
        dotAll: true,
      ).firstMatch(blockHtml);
      final snippet = _stripHtml(snippetMatch?.group(1) ?? '').trim();

      if (title.isNotEmpty) {
        results.add(_SearchResult(title: title, snippet: snippet));
      }
    }

    return results;
  }

  /// 移除 HTML 标签
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}

class _SearchResult {
  final String title;
  final String snippet;
  const _SearchResult({required this.title, required this.snippet});
}
