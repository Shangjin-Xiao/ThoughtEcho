import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/api_key_manager.dart';

void main() {
  group('APIKeyManager.isValidApiKeyFormat', () {
    late APIKeyManager manager;

    setUp(() {
      manager = APIKeyManager();
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

    test('accepts keys from providers without an sk- style prefix', () {
      // 回归：前缀白名单曾把这些合法密钥判成非法，导致每日提示、会话标题等
      // 依赖 hasValidProviderApiKey 的功能静默降级到本地兜底。
      expect(
        // Ollama Cloud：`<32位hex>.<后缀>`
        manager.isValidApiKeyFormat(
          '00000000000000000000000000000000.aaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        isTrue,
      );
      expect(
        // Google Gemini
        manager.isValidApiKeyFormat('AIzaSyTestKeyValueThatIsLongEnough123'),
        isTrue,
      );
      expect(
        // 智谱 GLM：`<id>.<secret>`
        manager.isValidApiKeyFormat('1234567890abcdef.AbCdEfGhIjKlMnOp'),
        isTrue,
      );
      expect(
        // API Ninjas：纯字母数字
        manager.isValidApiKeyFormat('AbCdEf0123456789AbCdEf0123456789'),
        isTrue,
      );
      expect(
        manager.isValidApiKeyFormat('this-is-not-a-provider-api-key-123456'),
        isTrue,
      );
    });

    test('rejects empty, too short and whitespace-tainted values', () {
      expect(manager.isValidApiKeyFormat(''), isFalse);
      expect(manager.isValidApiKeyFormat('   '), isFalse);
      expect(manager.isValidApiKeyFormat('short'), isFalse);
      // Bearer 前缀不参与长度判断
      expect(manager.isValidApiKeyFormat('Bearer short'), isFalse);
      // 粘贴时带进换行或中间空格
      expect(manager.isValidApiKeyFormat('sk-abc\ndef-1234567890'), isFalse);
      expect(manager.isValidApiKeyFormat('sk-abc def-1234567890'), isFalse);
    });

    test('trims surrounding whitespace before validating', () {
      expect(
        manager.isValidApiKeyFormat('  sk-test-key-1234567890\n'),
        isTrue,
      );
    });
  });
}
