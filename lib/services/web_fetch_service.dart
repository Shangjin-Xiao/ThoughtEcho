import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../utils/app_logger.dart';

/// 网页抓取超时异常
class WebFetchTimeoutException implements Exception {
  /// 错误消息
  final String message;

  /// 超时持续时间
  final Duration timeout;

  /// 构造函数
  WebFetchTimeoutException(this.message, this.timeout);

  @override
  String toString() => message;
}

/// Web抓取和解析服务
///
/// 提供网页内容抓取、解析和元数据提取功能
/// - 自动添加User-Agent头
/// - 10秒超时控制
/// - 完整的错误处理
/// - 清理脚本和样式标签
class WebFetchService {
  /// HTTP请求的User-Agent头
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// HTTP请求超时时间（秒）
  static const int _timeoutSeconds = 10;

  /// 用于剥离标签的正则表达式
  static final RegExp _scriptStyleTagsRegex =
      RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1\s*>', caseSensitive: false);

  /// 创建HTTP客户端
  ///
  /// 返回配置好的HTTP客户端，包含User-Agent头
  static http.Client _createClient() {
    return http.Client();
  }

  /// 获取并解析网页
  ///
  /// 从给定的URL获取网页内容，解析为HTML DOM树
  ///
  /// 参数:
  ///   - [url]: 要抓取的网址
  ///
  /// 返回: HTML文档树（html_dom.Document）
  ///
  /// 异常:
  ///   - 网络错误: 无法连接到URL
  ///   - 超时错误: 请求超过10秒
  ///   - 解析错误: HTML内容无法解析
  Future<html_dom.Document> fetchAndParse(String url) async {
    try {
      logDebug('开始抓取网页: $url');

      // 验证URL格式
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        final message = 'URL格式无效，必须以http://或https://开头: $url';
        logDebug(message);
        throw Exception(message);
      }

      final client = _createClient();
      try {
        // 发送GET请求，10秒超时
        final response = await client
            .get(
              Uri.parse(url),
              headers: {
                'User-Agent': _userAgent,
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
                'Accept-Encoding': 'gzip, deflate',
                'Connection': 'keep-alive',
              },
            )
            .timeout(
              Duration(seconds: _timeoutSeconds),
              onTimeout: () => throw WebFetchTimeoutException(
                '网页抓取超时（$_timeoutSeconds秒）',
                Duration(seconds: _timeoutSeconds),
              ),
            );

        logDebug('网页状态码: ${response.statusCode}');

        // 检查响应状态
        if (response.statusCode != 200) {
          final message =
              '网页请求失败: 状态码 ${response.statusCode}';
          logDebug(message);
          throw Exception(message);
        }

        // 检查Content-Type是否为HTML
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('html') && contentType.isNotEmpty) {
          logDebug('警告: Content-Type可能不是HTML: $contentType');
        }

        // 获取响应内容
        String htmlContent = response.body;
        logDebug('网页内容长度: ${htmlContent.length} 字节');

        // 清理脚本和样式标签（避免干扰解析）
        htmlContent = htmlContent.replaceAll(_scriptStyleTagsRegex, '');
        logDebug('清理后内容长度: ${htmlContent.length} 字节');

        // 解析HTML
        final document = html_parser.parse(htmlContent);
        logDebug('网页解析成功');

        return document;
      } finally {
        client.close();
      }
    } catch (e) {
      final errorMsg = '网页抓取异常: $e';
      logDebug(errorMsg);
      rethrow;
    }
  }

  /// 提取网页纯文本内容
  ///
  /// 从网页中提取所有文本内容，去除HTML标签
  ///
  /// 参数:
  ///   - [url]: 要抓取的网址
  ///
  /// 返回: 清理后的纯文本内容
  ///
  /// 异常: 同[fetchAndParse]
  Future<String> fetchText(String url) async {
    try {
      logDebug('开始提取网页纯文本: $url');

      final document = await fetchAndParse(url);

      // 移除script和style标签
      final scripts = document.querySelectorAll('script, style, noscript');
      for (final script in scripts) {
        script.remove();
      }

      // 获取body文本或整个文本
      String text = '';
      final body = document.querySelector('body');
      if (body != null) {
        text = body.text;
      } else {
        text = document.documentElement?.text ?? '';
      }

      // 清理多余的空白字符
      text = text.replaceAll(RegExp(r'\n\s*\n'), '\n'); // 移除多个空行
      text = text.replaceAll(RegExp(r' +'), ' '); // 多个空格合并为单个
      text = text.trim();

      logDebug('提取文本长度: ${text.length} 字符');

      return text;
    } catch (e) {
      final errorMsg = '纯文本提取异常: $e';
      logDebug(errorMsg);
      rethrow;
    }
  }

  /// 提取网页元数据
  ///
  /// 从网页中提取关键元数据，包括:
  /// - title: 网页标题(title标签)
  /// - description: 页面描述(meta description)
  /// - keywords: 页面关键词(meta keywords)
  /// - icon: 网站图标(favicon)
  /// - ogTitle: Open Graph标题
  /// - ogDescription: Open Graph描述
  /// - ogImage: Open Graph图片
  /// - author: 页面作者(meta author)
  /// - viewport: 视口配置(meta viewport)
  ///
  /// 参数:
  ///   - [url]: 要抓取的网址
  ///
  /// 返回: 包含元数据的Map (String到可为空String的映射)
  ///       值为null表示该元数据不存在
  ///
  /// 异常: 同[fetchAndParse]
  Future<Map<String, String?>> extractMetadata(String url) async {
    try {
      logDebug('开始提取网页元数据: $url');

      final document = await fetchAndParse(url);
      final metadata = <String, String?>{};

      // 提取标题
      final titleElement = document.querySelector('title');
      if (titleElement != null) {
        metadata['title'] = titleElement.text.trim();
      }
      logDebug('标题: ${metadata['title']}');

      // 提取meta标签信息
      final metaTags = document.querySelectorAll('meta');
      for (final meta in metaTags) {
        final name = meta.attributes['name']?.toLowerCase() ?? '';
        final property = meta.attributes['property']?.toLowerCase() ?? '';
        final content = meta.attributes['content'];

        if (content != null && content.isNotEmpty) {
          // 标准meta标签
          if (name == 'description') {
            metadata['description'] = content;
            logDebug('描述: $content');
          } else if (name == 'keywords') {
            metadata['keywords'] = content;
            logDebug('关键词: $content');
          } else if (name == 'author') {
            metadata['author'] = content;
            logDebug('作者: $content');
          } else if (name == 'viewport') {
            metadata['viewport'] = content;
          }

          // Open Graph标签
          if (property == 'og:title') {
            metadata['ogTitle'] = content;
            logDebug('OG标题: $content');
          } else if (property == 'og:description') {
            metadata['ogDescription'] = content;
            logDebug('OG描述: $content');
          } else if (property == 'og:image') {
            metadata['ogImage'] = content;
            logDebug('OG图片: $content');
          }
        }
      }

      // 提取favicon
      final linkTags = document.querySelectorAll('link');
      for (final link in linkTags) {
        final rel = link.attributes['rel']?.toLowerCase() ?? '';
        if (rel.contains('icon') || rel.contains('shortcut')) {
          final href = link.attributes['href'];
          if (href != null && href.isNotEmpty) {
            // 转换相对路径为绝对路径
            final faviconUrl = _resolveRelativeUrl(url, href);
            metadata['icon'] = faviconUrl;
            logDebug('图标: $faviconUrl');
            break;
          }
        }
      }

      logDebug('元数据提取完成，共${metadata.length}项');
      return metadata;
    } catch (e) {
      final errorMsg = '元数据提取异常: $e';
      logDebug(errorMsg);
      rethrow;
    }
  }

  /// 解析相对URL为绝对URL
  ///
  /// 参数:
  ///   - [baseUrl]: 基础URL（网页URL）
  ///   - [relativeUrl]: 相对或绝对URL
  ///
  /// 返回: 完整的绝对URL
  static String _resolveRelativeUrl(String baseUrl, String relativeUrl) {
    // 如果已经是绝对URL，直接返回
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }

    try {
      final baseUri = Uri.parse(baseUrl);

      // 处理协议相对URL（//example.com）
      if (relativeUrl.startsWith('//')) {
        return '${baseUri.scheme}:$relativeUrl';
      }

      // 处理绝对路径（/path）
      if (relativeUrl.startsWith('/')) {
        return '${baseUri.scheme}://${baseUri.host}$relativeUrl';
      }

      // 处理相对路径（./path 或 ../path）
      return baseUri.resolve(relativeUrl).toString();
    } catch (e) {
      logDebug('URL解析失败: $e');
      return relativeUrl; // 返回原始URL作为备选
    }
  }

  /// 验证URL是否可访问
  ///
  /// 发送HEAD请求以验证URL的可访问性，不下载完整内容
  ///
  /// 参数:
  ///   - [url]: 要验证的网址
  ///
  /// 返回: true表示URL可访问，false表示无法访问
  Future<bool> isUrlAccessible(String url) async {
    try {
      logDebug('验证URL可访问性: $url');

      final client = _createClient();
      try {
        final response = await client
            .head(
              Uri.parse(url),
              headers: {
                'User-Agent': _userAgent,
              },
            )
            .timeout(
              Duration(seconds: _timeoutSeconds),
            );

        final isAccessible = response.statusCode == 200;
        logDebug('URL可访问性: $isAccessible (状态码: ${response.statusCode})');
        return isAccessible;
      } finally {
        client.close();
      }
    } catch (e) {
      logDebug('URL验证异常: $e');
      return false;
    }
  }

  /// 获取网页标题
  ///
  /// 便捷方法，只提取网页的<title>标签内容
  ///
  /// 参数:
  ///   - [url]: 要抓取的网址
  ///
  /// 返回: 网页标题，如果获取失败则返回null
  Future<String?> getPageTitle(String url) async {
    try {
      final metadata = await extractMetadata(url);
      return metadata['title'];
    } catch (e) {
      logDebug('获取页面标题异常: $e');
      return null;
    }
  }

  /// 获取网页描述
  ///
  /// 便捷方法，优先返回Open Graph描述，其次返回meta description
  ///
  /// 参数:
  ///   - [url]: 要抓取的网址
  ///
  /// 返回: 网页描述，如果获取失败则返回null
  Future<String?> getPageDescription(String url) async {
    try {
      final metadata = await extractMetadata(url);
      return metadata['ogDescription'] ?? metadata['description'];
    } catch (e) {
      logDebug('获取页面描述异常: $e');
      return null;
    }
  }
}
