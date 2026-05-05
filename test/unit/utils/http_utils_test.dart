import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:thoughtecho/utils/http_utils.dart';
import 'dart:convert';

void main() {
  group('HttpUtils._convertDioResponseToHttpResponse', () {
    test('should correctly convert headers', () {
      final dioResponse = Response(
        requestOptions: RequestOptions(path: 'https://example.com'),
        statusCode: 200,
        headers: Headers.fromMap({
          'content-type': ['application/json'],
          'x-custom-header': ['value1', 'value2'],
        }),
        data: '{"success": true}',
      );

      final result = HttpUtils.convertDioResponseToHttpResponse(dioResponse);

      expect(result.statusCode, 200);
      expect(result.headers['content-type'], 'application/json');
      expect(result.headers['x-custom-header'], 'value1, value2');
      expect(result.body, '{"success": true}');
    });

    test('should handle hitokoto.cn API response (Map data)', () {
      final mapData = {'id': 1, 'hitokoto': 'Hello World'};
      final dioResponse = Response(
        requestOptions: RequestOptions(path: 'https://v1.hitokoto.cn'),
        statusCode: 200,
        headers: Headers(),
        data: mapData,
      );

      final result = HttpUtils.convertDioResponseToHttpResponse(dioResponse);

      expect(result.statusCode, 200);
      expect(result.body, json.encode(mapData));
    });

    test('should handle hitokoto.cn API response (String data)', () {
      final stringData = '{"id": 1, "hitokoto": "Hello World"}';
      final dioResponse = Response(
        requestOptions: RequestOptions(path: 'https://v1.hitokoto.cn'),
        statusCode: 200,
        headers: Headers(),
        data: stringData,
      );

      final result = HttpUtils.convertDioResponseToHttpResponse(dioResponse);

      expect(result.statusCode, 200);
      expect(result.body, stringData);
    });

    test('should handle hitokoto.cn API response (other type data)', () {
      final dioResponse = Response(
        requestOptions: RequestOptions(path: 'https://v1.hitokoto.cn'),
        statusCode: 200,
        headers: Headers(),
        data: 12345,
      );

      final result = HttpUtils.convertDioResponseToHttpResponse(dioResponse);

      expect(result.statusCode, 200);
      expect(result.body, '12345');
    });

    test('should handle normal API response (String data)', () {
      final dioResponse = Response(
        requestOptions: RequestOptions(path: 'https://api.example.com'),
        statusCode: 201,
        headers: Headers(),
        data: 'String Content',
      );

      final result = HttpUtils.convertDioResponseToHttpResponse(dioResponse);

      expect(result.statusCode, 201);
      expect(result.body, 'String Content');
    });

    test('should handle normal API response (other type data)', () {
      final dioResponse = Response(
        requestOptions: RequestOptions(path: 'https://api.example.com'),
        statusCode: 200,
        headers: Headers(),
        data: {'key': 'value'},
      );

      final result = HttpUtils.convertDioResponseToHttpResponse(dioResponse);

      expect(result.statusCode, 200);
      expect(result.body, '{key: value}'); // toString() output of Map
    });

    test('should handle missing statusCode', () {
      final dioResponse = Response(
        requestOptions: RequestOptions(path: 'https://api.example.com'),
        headers: Headers(),
        data: 'Content',
      );

      final result = HttpUtils.convertDioResponseToHttpResponse(dioResponse);

      expect(result.statusCode, 0); // Default when null
    });
  });
}
