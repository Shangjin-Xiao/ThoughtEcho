import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:thoughtecho/services/place_search_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this._responses);

  final List<http.Response> _responses;
  final List<Uri> requestedUris = <Uri>[];
  int _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUris.add(request.url);

    final response = _responses[_index < _responses.length
        ? _index
        : _responses.length - 1];
    _index++;

    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[
        utf8.encode(response.body),
      ]),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

void main() {
  group('NominatimPlaceSearchService', () {
    test('retries on 429 with configured backoff and eventually succeeds', () async {
      final fakeClient = _FakeClient(<http.Response>[
        http.Response('', 429),
        http.Response('', 429),
        http.Response('', 429),
        http.Response(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'name': 'Coffee Shop',
              'lat': '39.90',
              'lon': '116.40',
              'type': 'cafe',
              'address': <String, Object?>{
                'road': 'Main St',
                'city': 'Beijing',
              },
              'display_name': 'Coffee Shop, Main St, Beijing',
            },
          ]),
          200,
        ),
      ]);

      final delays = <Duration>[];
      final service = NominatimPlaceSearchService(
        httpClient: fakeClient,
        delay: (duration) async => delays.add(duration),
        debounceDuration: Duration.zero,
      );

      final results = await service.searchNearby(
        39.9,
        116.4,
        query: 'coffee',
      );

      expect(results, hasLength(1));
      expect(results.first.name, equals('Coffee Shop'));
      expect(fakeClient.requestedUris, hasLength(4));
      expect(
        delays,
        equals(<Duration>[
          const Duration(milliseconds: 500),
          const Duration(seconds: 1),
          const Duration(seconds: 2),
        ]),
      );
    });

    test('keeps only latest query and discards stale in-flight search', () async {
      final fakeClient = _FakeClient(<http.Response>[
        http.Response(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'name': 'New Result',
              'lat': '39.92',
              'lon': '116.42',
              'type': 'poi',
              'display_name': 'New Result, Beijing',
            },
          ]),
          200,
        ),
      ]);

      final firstDebounceGate = Completer<void>();
      var debounceCount = 0;
      Future<void> controlledDelay(Duration duration) async {
        if (duration > Duration.zero && debounceCount == 0) {
          debounceCount++;
          await firstDebounceGate.future;
        }
      }

      final service = NominatimPlaceSearchService(
        httpClient: fakeClient,
        delay: controlledDelay,
        debounceDuration: const Duration(milliseconds: 10),
      );

      final staleFuture = service.searchNearby(
        39.9,
        116.4,
        query: 'old',
      );

      final latestFuture = service.searchNearby(
        39.9,
        116.4,
        query: 'new',
      );

      firstDebounceGate.complete();

      final latestResult = await latestFuture;
      final staleResult = await staleFuture;

      expect(latestResult.any((p) => p.name == 'New Result'), isTrue);
      expect(service.lastResults.first.name, equals('New Result'));
      expect(staleResult.any((p) => p.name == 'Old Result'), isFalse);
      expect(fakeClient.requestedUris, hasLength(1));
      expect(fakeClient.requestedUris.first.queryParameters['q'], equals('new'));
    });
  });
}
