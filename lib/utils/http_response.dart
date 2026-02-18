/// 自定义HTTP响应类，兼容原http包的Response接口
/// 用于在迁移到Dio后保持API兼容性
class HttpResponse {
  /// 响应体内容
  final String body;

  /// HTTP状态码
  final int statusCode;

  /// 响应头
  final Map<String, String> headers;

  /// 响应内容长度
  int? get contentLength {
    // 查找 content-length 头部（不区分大小写）
    String? contentLengthHeader;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-length') {
        contentLengthHeader = entry.value;
        break;
      }
    }

    if (contentLengthHeader != null) {
      return int.tryParse(contentLengthHeader);
    }
    return body.length;
  }

  /// 构造函数
  HttpResponse(this.body, this.statusCode, {this.headers = const {}});

  /// 转换为字符串（返回响应体）
  @override
  String toString() => body;
}
