import 'dart:io';

import '../agent_tool.dart';
import '../web_fetch_service.dart';

/// 抓取网页内容，返回 Markdown 格式的正文
class WebFetchTool extends AgentTool {
  static const int _maxContentLength = 5000;

  final WebFetchService _webFetchService;

  const WebFetchTool(this._webFetchService);

  @override
  String get name => 'web_fetch';

  @override
  String get description => '【只读】抓取指定网页的内容。此工具仅用于获取信息。';

  @override
  bool get isReadOnly => true;

  @override
  bool get isConcurrencySafe => true;

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
    final trimmedUrl = url.trim();

    if (trimmedUrl.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'URL 不能为空',
        isError: true,
      );
    }

    if (!trimmedUrl.startsWith('http://') &&
        !trimmedUrl.startsWith('https://')) {
      return ToolResult(
        toolCallId: call.id,
        content: 'URL 格式无效，必须以 http:// 或 https:// 开头',
        isError: true,
      );
    }

    // SSRF Validation
    final uri = Uri.tryParse(trimmedUrl);
    if (uri != null) {
      final host = uri.host.toLowerCase().trim();
      var blocked = _isPrivateOrLocalHost(host);
      if (!blocked) {
        try {
          final resolved = await InternetAddress.lookup(host);
          blocked = resolved.any(
            (address) => _isPrivateOrLocalHost(address.address),
          );
        } catch (_) {
          blocked = true;
        }
      }
      if (blocked) {
        return ToolResult(
          toolCallId: call.id,
          content: '安全限制：不允许访问本地或私有网络地址。',
          isError: true,
        );
      }
    }

    try {
      final text = await _webFetchService.fetchText(trimmedUrl);

      if (text.isEmpty) {
        return ToolResult(toolCallId: call.id, content: '网页内容为空或无法提取文本内容。');
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

  bool _isPrivateOrLocalHost(String host) {
    if (host == 'localhost') return true;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) {
      return false;
    }
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
    if (ip.type == InternetAddressType.IPv4) {
      final bytes = ip.rawAddress;
      // 10.0.0.0/8
      if (bytes[0] == 10) return true;
      // 172.16.0.0/12
      if (bytes[0] == 172 && (bytes[1] >= 16 && bytes[1] <= 31)) return true;
      // 169.254.0.0/16
      if (bytes[0] == 169 && bytes[1] == 254) return true;
      // 192.168.0.0/16
      if (bytes[0] == 192 && bytes[1] == 168) return true;
    } else if (ip.type == InternetAddressType.IPv6) {
      final bytes = ip.rawAddress;
      if (bytes.isNotEmpty && (bytes[0] & 0xfe) == 0xfc) return true;
    }
    return false;
  }
}
