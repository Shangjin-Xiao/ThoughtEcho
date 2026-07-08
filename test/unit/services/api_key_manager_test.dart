import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/api_key_manager.dart';

void main() {
  group('APIKeyManager', () {
    late APIKeyManager manager;

    setUp(() {
      manager = APIKeyManager();
    });

    test('rejects long tokens without a supported provider prefix', () {
      expect(
        manager.isValidApiKeyFormat('this-is-not-a-provider-api-key-123456'),
        isFalse,
      );
    });

    test('accepts supported provider key prefixes', () {
      expect(manager.isValidApiKeyFormat('sk-test-key-1234567890'), isTrue);
      expect(manager.isValidApiKeyFormat('sk_test_key_1234567890'), isTrue);
      expect(manager.isValidApiKeyFormat('or_test_key_1234567890'), isTrue);
      expect(
        manager.isValidApiKeyFormat('Bearer test-token-1234567890'),
        isTrue,
      );
    });
  });
}
