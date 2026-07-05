import 'dart:convert';
import 'dart:io';

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
    try {
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
    } catch (e, stack) {
      logError(
        'WebFetchService.fetchText 失败: $url',
        error: e,
        stackTrace: stack,
        source: 'WebFetchService',
      );
      rethrow;
    }
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
    } catch (e, stack) {
      logError(
        '元数据提取异常',
        error: e,
        stackTrace: stack,
        source: 'WebFetchService',
      );
      rethrow;
    }
  }

  /// 验证 URL 是否可访问
  Future<bool> isUrlAccessible(String url) async {
    try {
      await validateUrlSafety(url);
      final client = http.Client();
      try {
        final response = await client.head(Uri.parse(url),
            headers: {'User-Agent': _userAgent}).timeout(_timeout);
        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (e, stack) {
      logError(
        'URL 验证异常',
        error: e,
        stackTrace: stack,
        source: 'WebFetchService',
      );
      return false;
    }
  }

  /// 获取网页标题
  Future<String?> getPageTitle(String url) async {
    final metadata = await extractMetadata(url);
    return metadata['title'];
  }

  // ── 内部方法 ──

  /// 验证 URL 安全性以防御 SSRF
  static Future<void> validateUrlSafety(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw Exception('URL 格式无效，必须以 http:// 或 https:// 开头: $url');
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw Exception('URL 无法解析: $url');
    }

    final host = uri.host.toLowerCase().trim();
    if (host.isEmpty) {
      throw Exception('URL 主机名为空: $url');
    }

    var blocked = isPrivateOrLocalHost(host);
    if (!blocked) {
      try {
        final resolved = await InternetAddress.lookup(host);
        blocked = resolved.any(
          (address) => isPrivateOrLocalHost(address.address),
        );
      } catch (_) {
        blocked = true;
      }
    }

    if (blocked) {
      throw Exception('安全限制：不允许访问本地或私有网络地址: $url');
    }
  }

  /// 检查主机名或 IP 是否为私有或本地地址
  static bool isPrivateOrLocalHost(String host) {
    if (host == 'localhost') return true;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) {
      return false;
    }
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
    if (ip.type == InternetAddressType.IPv4) {
      final bytes = ip.rawAddress;
      if (bytes[0] == 0) return true;
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
      if (_isIpv4MappedIpv6(bytes)) {
        return isPrivateOrLocalHost(
          '${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}',
        );
      }
    }
    return false;
  }

  static bool _isIpv4MappedIpv6(List<int> bytes) {
    if (bytes.length != 16) return false;
    for (var i = 0; i < 10; i++) {
      if (bytes[i] != 0) return false;
    }
    return bytes[10] == 0xff && bytes[11] == 0xff;
  }

  /// 抓取网页 HTML 原文
  Future<String> _fetchHtml(String url) async {
    await validateUrlSafety(url);

    logDebug('WebFetchService: 开始抓取 $url');
    final client = http.Client();
    try {
      final response = await _sendSafeRequest(client, Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception('网页请求失败: 状态码 ${response.statusCode}');
      }

      const maxSizeBytes = 2 * 1024 * 1024; // 2MB
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maxSizeBytes) {
        throw Exception('网页内容超出大小限制 (最大 2MB)');
      }

      final bytes = <int>[];
      int totalBytes = 0;
      await (() async {
        await for (final chunk in response.stream) {
          totalBytes += chunk.length;
          if (totalBytes > maxSizeBytes) {
            throw Exception('网页内容超出大小限制 (最大 2MB)');
          }
          bytes.addAll(chunk);
        }
      })()
          .timeout(
        _timeout,
        onTimeout: () => throw WebFetchTimeoutException(
          '网页抓取超时（${_timeout.inSeconds}秒）',
          _timeout,
        ),
      );

      final hasCharset =
          response.headers['content-type']?.toLowerCase().contains(
                    'charset=',
                  ) ??
              false;
      final body = hasCharset
          ? http.Response.bytes(
              bytes,
              response.statusCode,
              headers: response.headers,
            ).body
          : utf8.decode(bytes, allowMalformed: true);
      return body;
    } finally {
      client.close();
    }
  }

  Future<http.StreamedResponse> _sendSafeRequest(
    http.Client client,
    Uri initialUri,
  ) async {
    var uri = initialUri;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      await validateUrlSafety(uri.toString());
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        });

      final response = await client.send(request).timeout(
            _timeout,
            onTimeout: () => throw WebFetchTimeoutException(
              '网页抓取超时（${_timeout.inSeconds}秒）',
              _timeout,
            ),
          );

      if (!_isRedirectStatus(response.statusCode)) {
        return response;
      }

      await response.stream.drain();
      final location = response.headers['location'];
      if (location == null || location.trim().isEmpty) {
        throw Exception('网页重定向缺少 Location 响应头');
      }
      uri = uri.resolve(location.trim());
    }
    throw Exception('网页重定向次数过多');
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
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
