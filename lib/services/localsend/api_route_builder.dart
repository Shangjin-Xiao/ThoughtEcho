/// API路由构建器，用于LocalSend集成

class ApiRoute {
  static const ApiRouteConfig info = ApiRouteConfig._('/api/v1/info', '/api/v2/info');
  static const ApiRouteConfig register = ApiRouteConfig._('/api/v1/register', '/api/v2/register');
  static const ApiRouteConfig prepareUpload = ApiRouteConfig._('/api/v1/prepare-upload', '/api/v2/prepare-upload');
  static const ApiRouteConfig upload = ApiRouteConfig._('/api/v1/upload', '/api/v2/upload');
  static const ApiRouteConfig cancel = ApiRouteConfig._('/api/v1/cancel', '/api/v2/cancel');
  static const ApiRouteConfig show = ApiRouteConfig._('/api/v1/show', '/api/v2/show');
  static const ApiRouteConfig prepareDownload = ApiRouteConfig._('/api/v1/prepare-download', '/api/v2/prepare-download');
  static const ApiRouteConfig download = ApiRouteConfig._('/api/v1/download', '/api/v2/download');
}

class ApiRouteConfig {
  final String v1;
  final String v2;
  
  const ApiRouteConfig._(this.v1, this.v2);
  
  /// 根据设备和查询参数构建目标URL
  String target(dynamic device, {Map<String, String>? query}) {
    String baseUrl;
    if (device != null) {
      // 检查device是否有必需的属性
      final protocol = (device.https == true) ? 'https' : 'http';
      final port = device.port ?? 53317;
      final ip = device.ip ?? 'localhost';
      baseUrl = '$protocol://$ip:$port';
    } else {
      baseUrl = '';
    }
    
    String route = v2; // 默认使用v2
    
    if (query != null && query.isNotEmpty) {
      final queryString = query.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      route = '$route?$queryString';
    }
    
    return '$baseUrl$route';
  }
}
