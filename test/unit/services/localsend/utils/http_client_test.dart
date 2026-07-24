import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thoughtecho/services/localsend/utils/http_client.dart';

void main() {
  group('SimpleHttpClient', () {
    test('post request success', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://example.com/api?param=value');
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.body, jsonEncode({'key': 'value'}));
        return http.Response('{"result": "ok"}', 200);
      });

      final client = SimpleHttpClient(client: mockClient);
      final response = await client.post(
        'https://example.com/api',
        query: {'param': 'value'},
        body: {'key': 'value'},
      );

      expect(response.statusCode, 200);
      expect(response.body, '{"result": "ok"}');
      expect(response.bodyToJson, {'result': 'ok'});
    });

    test('post request without body', () async {
      final mockClient = MockClient((request) async {
        expect(request.body, isEmpty);
        return http.Response('', 201);
      });

      final client = SimpleHttpClient(client: mockClient);
      final response = await client.post('https://example.com/api');

      expect(response.statusCode, 201);
      expect(response.body, '');
    });

    test('post request failure throws HttpException', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network error');
      });

      final client = SimpleHttpClient(client: mockClient);

      expect(
        () => client.post('https://example.com/api'),
        throwsA(isA<HttpException>()),
      );
    });

    test('get request success', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://example.com/api?param=value');
        return http.Response('{"result": "ok"}', 200);
      });

      final client = SimpleHttpClient(client: mockClient);
      final response = await client.get(
        'https://example.com/api',
        query: {'param': 'value'},
      );

      expect(response.statusCode, 200);
      expect(response.body, '{"result": "ok"}');
    });

    test('get request failure throws HttpException', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network error');
      });

      final client = SimpleHttpClient(client: mockClient);

      expect(
        () => client.get('https://example.com/api'),
        throwsA(isA<HttpException>()),
      );
    });

    test('dispose closes the client', () {
      final spyClient = _SpyClient();
      final client = SimpleHttpClient(client: spyClient);
      client.dispose();
      expect(spyClient.closeCalled, isTrue);
    });

    test('post request respects CancelToken', () async {
      final mockClient = MockClient((request) async => http.Response('', 200));
      final client = SimpleHttpClient(client: mockClient);

      final token = CancelToken()..cancel();
      expect(
        () => client.post('https://example.com/api', cancelToken: token),
        throwsA(isA<HttpException>()
            .having((e) => e.message, 'message', 'Request cancelled')),
      );
    });

    test('get request respects CancelToken', () async {
      final mockClient = MockClient((request) async => http.Response('', 200));
      final client = SimpleHttpClient(client: mockClient);

      final token = CancelToken()..cancel();
      expect(
        () => client.get('https://example.com/api', cancelToken: token),
        throwsA(isA<HttpException>()
            .having((e) => e.message, 'message', 'Request cancelled')),
      );
    });
  });

  group('HttpTextResponse', () {
    test('bodyToJson parses valid json string', () {
      final response =
          HttpTextResponse(statusCode: 200, body: '{"key": "value"}');
      expect(response.bodyToJson, {'key': 'value'});
    });

    test('bodyToJson throws on invalid json', () {
      final response = HttpTextResponse(statusCode: 200, body: 'invalid json');
      expect(() => response.bodyToJson, throwsA(isA<FormatException>()));
    });
  });

  group('HttpException', () {
    test('properties and humanErrorMessage', () {
      final exception = HttpException('error message', 404);
      expect(exception.message, 'error message');
      expect(exception.statusCode, 404);
      expect(exception.humanErrorMessage, '[404] error message');
      expect(exception.toString(), 'HttpException: error message');
    });

    test('properties without statusCode', () {
      final exception = HttpException('error message');
      expect(exception.statusCode, isNull);
      expect(exception.humanErrorMessage, '[null] error message');
    });
  });

  group('CancelToken', () {
    test('initial state is not cancelled', () {
      final token = CancelToken();
      expect(token.isCancelled, isFalse);
    });

    test('cancel sets state to cancelled', () {
      final token = CancelToken();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });
  });

  group('HttpBody', () {
    test('json returns identical map', () {
      final data = {'key': 'value'};
      expect(HttpBody.json(data), equals(data));
    });
  });
}

class _SpyClient extends http.BaseClient {
  bool closeCalled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }

  @override
  void close() {
    closeCalled = true;
    super.close();
  }
}
