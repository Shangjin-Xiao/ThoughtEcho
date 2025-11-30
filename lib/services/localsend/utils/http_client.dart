import 'dart:convert';
import 'package:http/http.dart' as http;

/// Simplified HTTP client for ThoughtEcho LocalSend integration
class SimpleHttpClient {
  final http.Client _client = http.Client();

  Future<HttpTextResponse> post(
    String url, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(url).replace(queryParameters: query);

    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      );

      return HttpTextResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } catch (e) {
      throw HttpException(e.toString());
    }
  }

  Future<HttpTextResponse> get(
    String url, {
    Map<String, String>? query,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(url).replace(queryParameters: query);

    try {
      final response = await _client.get(uri);

      return HttpTextResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } catch (e) {
      throw HttpException(e.toString());
    }
  }

  void dispose() {
    _client.close();
  }
}

class HttpTextResponse {
  final int statusCode;
  final String body;

  HttpTextResponse({required this.statusCode, required this.body});

  dynamic get bodyToJson => jsonDecode(body);
}

class HttpException implements Exception {
  final String message;
  final int? statusCode;

  HttpException(this.message, [this.statusCode]);

  String get humanErrorMessage => '[$statusCode] $message';

  @override
  String toString() => 'HttpException: $message';
}

class CancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class HttpBody {
  static Map<String, dynamic> json(Map<String, dynamic> data) => data;
}
