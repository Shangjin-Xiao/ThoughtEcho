import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/sanitization_utils.dart';

void main() {
  group('sanitization_utils', () {
    group('isSensitiveKey', () {
      test('identifies base sensitive words and composite sensitive keys', () {
        expect(isSensitiveKey('content'), isTrue);
        expect(isSensitiveKey('text'), isTrue);
        expect(isSensitiveKey('noteText'), isTrue);
        expect(isSensitiveKey('rawContent'), isTrue);
        expect(isSensitiveKey('note_content'), isTrue);
        expect(isSensitiveKey('password'), isTrue);
        expect(isSensitiveKey('user_password'), isTrue);
        expect(isSensitiveKey('apiKey'), isTrue);
        expect(isSensitiveKey('api_key'), isTrue);
        expect(isSensitiveKey('secret_token'), isTrue);
        expect(isSensitiveKey('authorization'), isTrue);
        expect(isSensitiveKey('auth'), isTrue);
        expect(isSensitiveKey('authentication'), isTrue);
        expect(isSensitiveKey('credential'), isTrue);
        expect(isSensitiveKey('credentials'), isTrue);
        expect(isSensitiveKey('apikey'), isTrue);
        expect(isSensitiveKey('title'), isTrue);
        expect(isSensitiveKey('search_query'), isTrue);
      });

      test('exempts keys ending with metric suffixes', () {
        expect(isSensitiveKey('contentLength'), isFalse);
        expect(isSensitiveKey('text_length'), isFalse);
        expect(isSensitiveKey('query_count'), isFalse);
        expect(isSensitiveKey('tagCount'), isFalse);
        expect(isSensitiveKey('token_size'), isFalse);
        expect(isSensitiveKey('payload_bytes'), isFalse);
        expect(isSensitiveKey('request_duration'), isFalse);
        expect(isSensitiveKey('duration_ms'), isFalse);
        expect(isSensitiveKey('memory_overhead'), isFalse);
        expect(isSensitiveKey('vsyncOverhead'), isFalse);
      });

      test('allows normal safe keys', () {
        expect(isSensitiveKey('mode'), isFalse);
        expect(isSensitiveKey('status'), isFalse);
        expect(isSensitiveKey('userId'), isFalse);
        expect(isSensitiveKey('index'), isFalse);
        expect(isSensitiveKey('inset'), isFalse);
        expect(isSensitiveKey('frameJank'), isFalse);
        expect(isSensitiveKey('budgetMs'), isFalse);
        expect(isSensitiveKey(''), isFalse);
      });

      test('supports custom sensitive words and metric suffixes', () {
        expect(
          isSensitiveKey('customKey', sensitiveWords: {'custom'}),
          isTrue,
        );
        expect(
          isSensitiveKey(
            'customKey_metric',
            sensitiveWords: {'custom'},
            metricSuffixes: {'metric'},
          ),
          isFalse,
        );
      });
    });

    group('isLikelyUrl and sanitizeUrl', () {
      test('isLikelyUrl identifies URL strings correctly', () {
        expect(isLikelyUrl('https://example.com/api/test'), isTrue);
        expect(isLikelyUrl('http://localhost:8080/data'), isTrue);
        expect(isLikelyUrl('file:///local/mock/data.json'), isTrue);
        expect(isLikelyUrl('/api/v1/notes', 'url'), isTrue);
        expect(isLikelyUrl('custom://deep/link'), isTrue);

        expect(isLikelyUrl('FormatException: bad input string'), isFalse);
        expect(isLikelyUrl('plain text description'), isFalse);
        expect(isLikelyUrl('/relative/path/without/url/key'), isFalse);
      });

      test('sanitizeUrl handles null and invalid urls', () {
        expect(sanitizeUrl(null), isNull);
        expect(sanitizeUrl(''), '');
      });

      test('sanitizeUrl scrubs queries and fragments from http/https URLs', () {
        expect(
          sanitizeUrl('https://example.com/api/v1/notes?query=secret#fragment'),
          'https://example.com/api/v1/notes',
        );
        expect(
          sanitizeUrl('http://service.internal:8080/path?apiKey=xyz'),
          'http://service.internal:8080/path',
        );
      });

      test('sanitizeUrl redacts file scheme to [path]', () {
        expect(sanitizeUrl('file:///local/mock/path/note.txt'), '[path]');
        expect(sanitizeUrl('FILE:///storage/mock/photo.jpg'), '[path]');
      });

      test('sanitizeUrl handles relative paths and non-URL text', () {
        expect(sanitizeUrl('/relative/path/notes'), '/relative/path/notes');
        expect(
          sanitizeUrl('/relative/path/notes?ignored=true#hash'),
          '/relative/path/notes',
        );
      });
    });

    group('sanitizeDataValue and sanitizeDataMap', () {
      test('filters sensitive keys from top-level map', () {
        final data = <String, dynamic>{
          'content': 'Secret note content',
          'password': 'my-secret-password',
          'token': 'bearer-token-123',
          'apiKey': 'mock-api-key',
          'secret': 'classified',
          'mode': 'preview',
          'status': 200,
        };

        final sanitized = sanitizeDataMap(data);

        expect(sanitized, isNot(contains('content')));
        expect(sanitized, isNot(contains('password')));
        expect(sanitized, isNot(contains('token')));
        expect(sanitized, isNot(contains('apiKey')));
        expect(sanitized, isNot(contains('secret')));
        expect(sanitized['mode'], 'preview');
        expect(sanitized['status'], 200);
      });

      test('removes http.query and http.fragment keys', () {
        final data = <String, dynamic>{
          'http.query': 'auth=token123',
          'http.fragment': 'targetSection',
          'operation': 'sync',
        };

        final sanitized = sanitizeDataMap(data);

        expect(sanitized, isNot(contains('http.query')));
        expect(sanitized, isNot(contains('http.fragment')));
        expect(sanitized['operation'], 'sync');
      });

      test('preserves exempted metric keys', () {
        final data = <String, dynamic>{
          'contentLength': 1024,
          'text_length': 256,
          'query_count': 5,
          'duration_ms': 12.4,
          'token_size': 32,
          'memory_overhead': 4096,
        };

        final sanitized = sanitizeDataMap(data);

        expect(sanitized['contentLength'], 1024);
        expect(sanitized['text_length'], 256);
        expect(sanitized['query_count'], 5);
        expect(sanitized['duration_ms'], 12.4);
        expect(sanitized['token_size'], 32);
        expect(sanitized['memory_overhead'], 4096);
      });

      test('sanitizes nested Map, List, and URLs recursively', () {
        final data = <String, dynamic>{
          'endpoint': 'https://api.example.com/v1/search?token=secret123#top',
          'url': 'https://example.com/item?api_key=mock_key',
          'fileUrl': 'file:///local/mock/document.pdf',
          'metadata': <String, dynamic>{
            'title': 'Sensitive title',
            'query': 'Sensitive query',
            'validKey': 'keep-me',
            'nestedUrl': 'https://nested.example.com/data?user=mock#sec',
          },
          'items': <dynamic>[
            'https://item.example.com/res?secret=abc',
            <String, dynamic>{
              'token': 'inner_token',
              'count': 10,
              'http.query': 'dropped',
            },
            <dynamic>[
              <String, dynamic>{
                'credential': 'inner_credential',
                'overhead': 50,
              },
            ],
            'plain string value',
            42,
            true,
          ],
          'nonStringMap': <dynamic, dynamic>{
            1: 'numeric_key_val',
            'password': 'bad_password',
          },
        };

        final sanitized = sanitizeDataMap(data);

        expect(sanitized['endpoint'], 'https://api.example.com/v1/search');
        expect(sanitized['url'], 'https://example.com/item');
        expect(sanitized['fileUrl'], '[path]');

        final metadata = sanitized['metadata'] as Map<dynamic, dynamic>;
        expect(metadata, isNot(contains('title')));
        expect(metadata, isNot(contains('query')));
        expect(metadata['validKey'], 'keep-me');
        expect(metadata['nestedUrl'], 'https://nested.example.com/data');

        final items = sanitized['items'] as List<dynamic>;
        expect(items[0], 'https://item.example.com/res');
        final itemMap = items[1] as Map<dynamic, dynamic>;
        expect(itemMap, isNot(contains('token')));
        expect(itemMap, isNot(contains('http.query')));
        expect(itemMap['count'], 10);

        final deepList = items[2] as List<dynamic>;
        final deepMap = deepList[0] as Map<dynamic, dynamic>;
        expect(deepMap, isNot(contains('credential')));
        expect(deepMap['overhead'], 50);

        expect(items[3], 'plain string value');
        expect(items[4], 42);
        expect(items[5], isTrue);

        final nonStringMap = sanitized['nonStringMap'] as Map<dynamic, dynamic>;
        expect(nonStringMap[1], 'numeric_key_val');
        expect(nonStringMap, isNot(contains('password')));
      });

      test('sanitizeDataValue handles primitive types and null directly', () {
        expect(sanitizeDataValue(null), isNull);
        expect(sanitizeDataValue(123), 123);
        expect(sanitizeDataValue(3.14), 3.14);
        expect(sanitizeDataValue(true), isTrue);
        expect(
          sanitizeDataValue('https://example.com/path?query=val#ref'),
          'https://example.com/path',
        );
        expect(sanitizeDataValue('plain text'), 'plain text');
      });

      test('sanitizeDataMap works with custom isSensitive predicate', () {
        final data = <String, dynamic>{
          'custom_secret': 'hidden',
          'normal_key': 'visible',
        };

        final sanitized = sanitizeDataMap(
          data,
          isSensitive: (k) => k.startsWith('custom_'),
        );

        expect(sanitized, isNot(contains('custom_secret')));
        expect(sanitized['normal_key'], 'visible');
      });
    });
  });
}
