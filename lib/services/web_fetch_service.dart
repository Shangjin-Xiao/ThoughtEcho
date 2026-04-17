import 'package:html/parser.dart' as html_parser;
import 'package:html2md/html2md.dart' as html2md;
import 'package:http/http.dart' as http;

import '../utils/app_logger.dart';

/// 网页抓取超时异常
class WebFetchTimeoutException implements Exception {
  final String message;
  final Duration timeout;

  WebFetchTimeoutException(this.message, this.timeout);

  @override
  String toString() => message;
}

/// Web 抓取服务
///
/// 抓取网页 HTML 并转换为 Markdown，保留标题、链接、列表等结构，
/// 便于 LLM 理解和处理。
class WebFetchService {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const Duration _timeout = Duration(seconds: 15);

  /// 需要移除的 HTML 标签（导航、广告、脚本等无用元素）
  static const _stripTags = [
    'script',
    'style',
    'noscript',
    'nav',
    'footer',
    'header',
    'iframe',
  ];

  /// 抓取网页并转换为 Markdown 格式
  ///
  /// Markdown 保留了标题、链接、列表等结构信息，
  /// 对 LLM 理解网页内容比纯文本更友好。
  Future<String> fetchText(String url) async {
    final rawHtml = await _fetchHtml(url);

    // 先清理无用标签，再转 Markdown
    final cleanedHtml = _stripNoiseTags(rawHtml);
    final markdown = html2md.convert(
      cleanedHtml,
      styleOptions: {'headingStyle': 'atx'},
      ignore: ['img'],
    );

    final result = _normalizeWhitespace(markdown);
    logDebug('WebFetchService: 转换完成（${result.length} 字符）');
    return result;
  }

  /// 提取网页元数据（标题、描述、图片）
  Future<Map<String, String?>> extractMetadata(String url) async {
    try {
      final html = await _fetchHtml(url);
      final document = html_parser.parse(html);

      final title = document.querySelector('title')?.text ??
          document
              .querySelector('meta[property="og:title"]')
              ?.attributes['content'];
      final description = document
              .querySelector('meta[name="description"]')
              ?.attributes['content'] ??
          document
              .querySelector('meta[property="og:description"]')
              ?.attributes['content'];
      final image = document
          .querySelector('meta[property="og:image"]')
          ?.attributes['content'];

      return {
        'title': title,
        'description': description,
        'image': image,
        'url': url,
      };
    } catch (e) {
      logDebug('元数据提取异常: $e');
      rethrow;
    }
  }

  /// 验证 URL 是否可访问
  Future<bool> isUrlAccessible(String url) async {
    try {
      final client = http.Client();
      try {
        final response = await client
            .head(Uri.parse(url), headers: {'User-Agent': _userAgent})
            .timeout(_timeout);
        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (e) {
      logDebug('URL 验证异常: $e');
      return false;
    }
  }

  /// 获取网页标题
  Future<String?> getPageTitle(String url) async {
    final metadata = await extractMetadata(url);
    return metadata['title'];
  }

  // ── 内部方法 ──

  /// 抓取网页 HTML 原文
  Future<String> _fetchHtml(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw Exception('URL 格式无效，必须以 http:// 或 https:// 开头: $url');
    }

    logDebug('WebFetchService: 开始抓取 $url');
    final client = http.Client();
    try {
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(
        _timeout,
        onTimeout: () => throw WebFetchTimeoutException(
          '网页抓取超时（${_timeout.inSeconds}秒）',
          _timeout,
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('网页请求失败: 状态码 ${response.statusCode}');
      }

      return response.body;
    } finally {
      client.close();
    }
  }

  /// 移除 HTML 中的噪声标签
  static String _stripNoiseTags(String html) {
    final document = html_parser.parse(html);
    for (final tag in _stripTags) {
      document.querySelectorAll(tag).forEach((e) => e.remove());
    }
    return document.outerHtml;
  }

  /// 规范化空白字符
  static String _normalizeWhitespace(String text) {
    return text
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r' +'), ' ')
        .trim();
  }
}
