import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/streaming_utils.dart';

void main() {
  group('StreamingUtils.extractContentFromLine', () {
    test('extracts content from new format (delta.content)', () {
      final jsonString = jsonEncode({
        'choices': [
          {
            'delta': {'content': 'Hello, world!'}
          }
        ]
      });
      final line = 'data: $jsonString';
      final result = StreamingUtils.extractContentFromLine(line);
      expect(result, 'Hello, world!');
    });

    test('extracts content from old format (text)', () {
      final jsonString = jsonEncode({
        'choices': [
          {'text': 'Old format text'}
        ]
      });
      final line = 'data: $jsonString';
      final result = StreamingUtils.extractContentFromLine(line);
      expect(result, 'Old format text');
    });

    test('returns null for empty choices', () {
      final jsonString = jsonEncode({'choices': []});
      final line = 'data: $jsonString';
      final result = StreamingUtils.extractContentFromLine(line);
      expect(result, isNull);
    });

    test('returns null for missing content and text', () {
      final jsonString = jsonEncode({
        'choices': [
          {
            'delta': {'role': 'assistant'}
          }
        ]
      });
      final line = 'data: $jsonString';
      final result = StreamingUtils.extractContentFromLine(line);
      expect(result, isNull);
    });

    test('returns null for invalid JSON', () {
      final line = 'data: {invalid json}';
      final result = StreamingUtils.extractContentFromLine(line);
      expect(result, isNull);
    });

    test('returns null for non-string content', () {
      final jsonString = jsonEncode({
        'choices': [
          {
            'delta': {'content': 123}
          }
        ]
      });
      final line = 'data: $jsonString';
      final result = StreamingUtils.extractContentFromLine(line);
      expect(result, isNull);
    });
  });

  group('StreamingUtils.parseErrorMessage', () {
    test('parses 429 rate limit error', () {
      final msg = StreamingUtils.parseErrorMessage(429, 'rate_limit_exceeded');
      expect(msg, contains('请求频率超限'));
      expect(msg, contains('429'));
    });

    test('parses 401 unauthorized error', () {
      final msg = StreamingUtils.parseErrorMessage(401, 'invalid_api_key');
      expect(msg, contains('API密钥无效'));
      expect(msg, contains('401'));
    });

    test('parses quota insufficient error', () {
      final msg = StreamingUtils.parseErrorMessage(400, 'insufficient_quota');
      expect(msg, contains('API额度不足'));
    });

    test('parses 500 internal server error with JSON detail', () {
      final errorJson = jsonEncode({
        'error': {'message': 'Custom error message'}
      });
      final msg = StreamingUtils.parseErrorMessage(500, errorJson);
      expect(msg, contains('AI服务器内部错误 (500)'));
      expect(msg, contains('Custom error message'));
    });

    test('parses 500 error with model not found fallback', () {
      final msg = StreamingUtils.parseErrorMessage(500, 'model does not exist');
      expect(msg, contains('AI服务器内部错误 (500)'));
      expect(msg, contains('可能是模型不存在或不可用'));
    });

    test('parses 502/503/504 gateway errors', () {
      final msg502 = StreamingUtils.parseErrorMessage(502, 'Bad Gateway');
      expect(msg502, contains('AI服务暂时不可用'));
      expect(msg502, contains('502'));
    });

    test('parses unknown error code', () {
      final msg = StreamingUtils.parseErrorMessage(418, 'I am a teapot');
      expect(msg, contains('AI服务请求失败：418'));
      expect(msg, contains('I am a teapot'));
    });
  });
}
