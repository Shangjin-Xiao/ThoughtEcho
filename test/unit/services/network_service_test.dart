import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/network_service.dart';

void main() {
  group('NetworkService - AI Stream Parsing', () {
    late NetworkService networkService;

    setUp(() {
      networkService = NetworkService.instance;
    });

    test('should parse OpenAI format correctly', () async {
      final controller = StreamController<List<int>>();
      final receivedData = <String>[];
      String completedContent = '';

      final future = networkService.processAIStreamResponse(
        controller.stream,
        (data) => receivedData.add(data),
        (complete) => completedContent = complete,
        (error) => fail('Should not error: $error'),
      );

      controller.add(
        utf8.encode('data: {"choices": [{"delta": {"content": "Hello"}}]}\n'),
      );
      controller.add(
        utf8.encode('data: {"choices": [{"delta": {"content": " world"}}]}\n'),
      );
      controller.add(utf8.encode('data: [DONE]\n'));
      await controller.close();
      await future;

      expect(receivedData, ['Hello', ' world']);
      expect(completedContent, 'Hello world');
    });

    test('should parse Anthropic format correctly', () async {
      final controller = StreamController<List<int>>();
      final receivedData = <String>[];
      String completedContent = '';

      final future = networkService.processAIStreamResponse(
        controller.stream,
        (data) => receivedData.add(data),
        (complete) => completedContent = complete,
        (error) => fail('Should not error: $error'),
      );

      controller.add(utf8.encode('data: {"delta": {"text": "Hi"}}\n'));
      controller.add(utf8.encode('data: {"delta": {"text": " there"}}\n'));
      controller.add(utf8.encode('data: [DONE]\n'));
      await controller.close();
      await future;

      expect(receivedData, ['Hi', ' there']);
      expect(completedContent, 'Hi there');
    });

    test('should handle split chunks correctly', () async {
      final controller = StreamController<List<int>>();
      final receivedData = <String>[];
      String completedContent = '';

      final future = networkService.processAIStreamResponse(
        controller.stream,
        (data) => receivedData.add(data),
        (complete) => completedContent = complete,
        (error) => fail('Should not error: $error'),
      );

      // Split "data: {"choices": [{"delta": {"content": "Part"}}]}\n"
      controller.add(utf8.encode('data: {"choices": [{"de'));
      controller.add(utf8.encode('lta": {"content": "Part"}}]}\n'));
      controller.add(utf8.encode('data: [DONE]\n'));
      await controller.close();
      await future;

      expect(receivedData, ['Part']);
      expect(completedContent, 'Part');
    });

    test('should handle multiple lines in one chunk', () async {
      final controller = StreamController<List<int>>();
      final receivedData = <String>[];
      String completedContent = '';

      final future = networkService.processAIStreamResponse(
        controller.stream,
        (data) => receivedData.add(data),
        (complete) => completedContent = complete,
        (error) => fail('Should not error: $error'),
      );

      controller.add(
        utf8.encode(
          'data: {"choices": [{"delta": {"content": "Line1"}}]}\n'
          'data: {"choices": [{"delta": {"content": "Line2"}}]}\n'
          'data: [DONE]\n',
        ),
      );
      await controller.close();
      await future;

      expect(receivedData, ['Line1', 'Line2']);
      expect(completedContent, 'Line1Line2');
    });

    test('should skip invalid JSON gracefully', () async {
      final controller = StreamController<List<int>>();
      final receivedData = <String>[];
      String completedContent = '';

      final future = networkService.processAIStreamResponse(
        controller.stream,
        (data) => receivedData.add(data),
        (complete) => completedContent = complete,
        (error) => fail('Should not error: $error'),
      );

      controller.add(utf8.encode('data: {invalid_json}\n'));
      controller.add(
        utf8.encode('data: {"choices": [{"delta": {"content": "Valid"}}]}\n'),
      );
      controller.add(utf8.encode('data: [DONE]\n'));
      await controller.close();
      await future;

      expect(receivedData, ['Valid']);
      expect(completedContent, 'Valid');
    });

    test('should handle [DONE] signal and stop processing', () async {
      final controller = StreamController<List<int>>();
      final receivedData = <String>[];
      String completedContent = '';

      final future = networkService.processAIStreamResponse(
        controller.stream,
        (data) => receivedData.add(data),
        (complete) => completedContent = complete,
        (error) => fail('Should not error: $error'),
      );

      controller.add(
        utf8.encode('data: {"choices": [{"delta": {"content": "Before"}}]}\n'),
      );
      controller.add(utf8.encode('data: [DONE]\n'));
      controller.add(
        utf8.encode('data: {"choices": [{"delta": {"content": "After"}}]}\n'),
      );
      await controller.close();
      await future;

      expect(receivedData, ['Before']);
      expect(completedContent, 'Before');
    });

    test('should call onError on stream exception', () async {
      final controller = StreamController<List<int>>();
      final receivedData = <String>[];
      Exception? caughtError;

      final future = networkService.processAIStreamResponse(
        controller.stream,
        (data) => receivedData.add(data),
        (complete) {},
        (error) => caughtError = error,
      );

      controller.add(
        utf8.encode('data: {"choices": [{"delta": {"content": "Good"}}]}\n'),
      );
      controller.addError(Exception('Stream failed'));
      await controller.close().catchError((_) {});
      await future;

      expect(receivedData, ['Good']);
      expect(caughtError.toString(), contains('Stream failed'));
    });
  });
}
