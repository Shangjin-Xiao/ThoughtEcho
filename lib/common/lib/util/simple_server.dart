/// Simple server utilities for LocalSend
import 'dart:io';
import 'dart:convert';

class SimpleServerRouteBuilder {
  void get(String path, Future<void> Function(HttpRequest) handler) {
    // Route handler implementation
  }

  void post(String path, Future<void> Function(HttpRequest) handler) {
    // Route handler implementation  
  }
}

extension HttpRequestExtensions on HttpRequest {
  String get ip => connectionInfo?.remoteAddress.address ?? '';
  
  Map<String, dynamic>? get deviceInfo => null;
  
  Future<void> respondJson(int statusCode, {Map<String, dynamic>? body, String? message}) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    
    final responseBody = body ?? {'message': message ?? 'OK'};
    response.write(jsonEncode(responseBody));
    await response.close();
  }
  
  Future<void> respondAsset(int statusCode, String assetPath, [String? contentType]) async {
    response.statusCode = statusCode;
    if (contentType != null) {
      response.headers.set('content-type', contentType);
    }
    response.write('Asset: $assetPath');
    await response.close();
  }
}