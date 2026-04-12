import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import '../web_fetch_service.dart';

/// 抓取网页内容，获取网页的纯文本信息
class WebFetchTool extends AgentTool {
  static const int _maxContentLength = 4000;

  final WebFetchService _webFetchService;

  const WebFetchTool(this._webFetchService);

  @override
  String get name => 'web_fetch';

  @override
  String get description => '【只读】抓取指定网页的内容。此工具仅用于获取信息。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': '要抓取的网页URL（必须以 http:// 或 https:// 开头）',
          },
        },
        'required': ['url'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final url = call.getString('url');

    if (url.trim().isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'URL 不能为空',
        isError: true,
      );
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return ToolResult(
        toolCallId: call.id,
        content: 'URL 格式无效，必须以 http:// 或 https:// 开头',
        isError: true,
      );
    }

    try {
      final text = await _webFetchService.fetchText(url);

      if (text.isEmpty) {
        return ToolResult(
          toolCallId: call.id,
          content: '网页内容为空或无法提取文本内容。',
        );
      }

      // Truncate if too long
      final truncated = text.length > _maxContentLength
          ? '${text.substring(0, _maxContentLength)}…\n\n[内容已截断，共 ${text.length} 字符]'
          : text;

      return ToolResult(toolCallId: call.id, content: truncated);
    } catch (e, stack) {
      call.logError('WebFetchTool.execute 失败', error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '网页抓取失败：$e',
        isError: true,
      );
    }
  }
}
