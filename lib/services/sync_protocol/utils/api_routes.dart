/// API路由构建器
/// 用于构建ThoughtEcho同步协议的API路径
library;

import '../models/device_info.dart';
import '../constants.dart';

/// API路由枚举
enum ApiRoute {
  info,
  prepareUpload,
  upload,
  cancel,
}

/// API路由构建器
class ApiRoutes {
  /// 构建API URL
  static String buildUrl(NetworkDevice device, ApiRoute route, {Map<String, String>? params}) {
    final baseUrl = device.baseUrl;
    final path = _getPath(route);
    
    if (params == null || params.isEmpty) {
      return '$baseUrl$path';
    }
    
    final query = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    
    return '$baseUrl$path?$query';
  }

  /// 获取路径
  static String _getPath(ApiRoute route) {
    switch (route) {
      case ApiRoute.info:
        return ApiPaths.info;
      case ApiRoute.prepareUpload:
        return ApiPaths.prepareUpload;
      case ApiRoute.upload:
        return ApiPaths.upload;
      case ApiRoute.cancel:
        return ApiPaths.cancel;
    }
  }

  /// 构建信息查询URL
  static String info(NetworkDevice device) {
    return buildUrl(device, ApiRoute.info);
  }

  /// 构建准备上传URL
  static String prepareUpload(NetworkDevice device) {
    return buildUrl(device, ApiRoute.prepareUpload);
  }

  /// 构建上传URL
  static String upload(NetworkDevice device, {required String sessionId, required String fileId, required String token}) {
    return buildUrl(device, ApiRoute.upload, params: {
      'sessionId': sessionId,
      'fileId': fileId,
      'token': token,
    });
  }

  /// 构建取消URL
  static String cancel(NetworkDevice device, {required String sessionId}) {
    return buildUrl(device, ApiRoute.cancel, params: {
      'sessionId': sessionId,
    });
  }
}
