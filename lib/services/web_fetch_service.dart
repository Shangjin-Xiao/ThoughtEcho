import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:metadata_fetch/metadata_fetch.dart';
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
/// - 使用 metadata_fetch 获取 SOTA 元数据
/// - 自动添加User-Agent头
/// - 10秒超时控制
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
  static http.Client _createClient() {
    return http.Client();
  }

  /// 获取并解析网页
  Future<html_dom.Document> fetchAndParse(String url) async {
    try {
      logDebug('开始抓取网页: $url');

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        throw Exception('URL格式无效，必须以http://或https://开头: $url');
      }

      final client = _createClient();
      try {
        final response = await client
            .get(
              Uri.parse(url),
              headers: {
                'User-Agent': _userAgent,
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              },
            )
            .timeout(
              Duration(seconds: _timeoutSeconds),
              onTimeout: () => throw WebFetchTimeoutException(
                '网页抓取超时（$_timeoutSeconds秒）',
                Duration(seconds: _timeoutSeconds),
              ),
            );

        if (response.statusCode != 200) {
          throw Exception('网页请求失败: 状态码 ${response.statusCode}');
        }

        String htmlContent = response.body;
        htmlContent = htmlContent.replaceAll(_scriptStyleTagsRegex, '');
        return html_parser.parse(htmlContent);
      } finally {
        client.close();
      }
    } catch (e) {
      logDebug('网页抓取异常: $e');
      rethrow;
    }
  }

  /// 提取网页纯文本内容
  Future<String> fetchText(String url) async {
    try {
      logDebug('开始提取网页纯文本: $url');

      // 1. 尝试使用 metadata_fetch 提取元数据和可能的正文
      final metadata = await MetadataFetch.extract(url);
      
      // 检查 package 是否返回了足够丰富的描述作为正文
      if (metadata != null && metadata.description != null && metadata.description!.length > 500) {
        logDebug('使用 metadata_fetch 提供的描述作为主要内容');
        return metadata.description!.trim();
      }

      // 2. 降级到手动 HTML 解析以获取全文
      logDebug('metadata_fetch 内容有限，降级到手动解析');
      final document = await fetchAndParse(url);

      final scripts = document.querySelectorAll('script, style, noscript');
      for (final script in scripts) {
        script.remove();
      }

      String text = '';
      final body = document.querySelector('body');
      if (body != null) {
        text = body.text;
      } else {
        text = document.documentElement?.text ?? '';
      }

      text = text.replaceAll(RegExp(r'\n\s*\n'), '\n');
      text = text.replaceAll(RegExp(r' +'), ' ');
      return text.trim();
    } catch (e) {
      logDebug('纯文本提取异常: $e');
      rethrow;
    }
  }

  /// 提取网页元数据
  Future<Map<String, String?>> extractMetadata(String url) async {
    try {
      logDebug('开始提取网页元数据: $url');

      // 使用 metadata_fetch 提取 SOTA 元数据
      final metadata = await MetadataFetch.extract(url);
      
      if (metadata == null) {
        logDebug('metadata_fetch 未能提取到元数据');
        return {};
      }

      final result = {
        'title': metadata.title,
        'description': metadata.description,
        'image': metadata.image,
        'url': metadata.url,
      };

      logDebug('元数据提取完成: ${result['title']}');
      return result;
    } catch (e) {
      logDebug('元数据提取异常: $e');
      rethrow;
    }
  }

  /// 验证URL是否可访问
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
  Future<String?> getPageDescription(String url) async {
    try {
      final metadata = await extractMetadata(url);
      return metadata['description'];
    } catch (e) {
      logDebug('获取页面描述异常: $e');
      return null;
    }
  }
}
