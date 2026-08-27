import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/ai_endpoint_security.dart';

void main() {
  group('isSecureAiEndpointUrl', () {
    test('https 一律放行，大小写不敏感', () {
      expect(isSecureAiEndpointUrl('https://api.openai.com/v1/x'), isTrue);
      expect(isSecureAiEndpointUrl('HTTPS://api.openai.com/v1/x'), isTrue);
    });

    test('公网明文一律拦下', () {
      expect(isSecureAiEndpointUrl('http://api.openai.com/v1/x'), isFalse);
      expect(isSecureAiEndpointUrl('http://8.8.8.8:11434/v1'), isFalse);
      // 172.15 / 172.32 在 RFC1918 的 172.16/12 之外，别把边界放宽了。
      expect(isSecureAiEndpointUrl('http://172.15.0.1:1234/v1'), isFalse);
      expect(isSecureAiEndpointUrl('http://172.32.0.1:1234/v1'), isFalse);
    });

    test('本地模型的明文端点放行——这是 Ollama / LM Studio 唯一的部署形态', () {
      expect(isSecureAiEndpointUrl('http://localhost:1234/v1'), isTrue);
      expect(isSecureAiEndpointUrl('http://127.0.0.1:11434/v1'), isTrue);
      expect(isSecureAiEndpointUrl('http://[::1]:11434/v1'), isTrue);
      expect(isSecureAiEndpointUrl('http://mac-mini.local:1234/v1'), isTrue);
    });

    test('私有网段的明文端点放行：包没有离开本地网络', () {
      expect(isSecureAiEndpointUrl('http://192.168.1.10:11434/v1'), isTrue);
      expect(isSecureAiEndpointUrl('http://10.0.0.5:11434/v1'), isTrue);
      expect(isSecureAiEndpointUrl('http://172.16.0.1:11434/v1'), isTrue);
      expect(isSecureAiEndpointUrl('http://172.31.255.254:1234/v1'), isTrue);
      expect(isSecureAiEndpointUrl('http://[fd00::1]:11434/v1'), isTrue);
    });

    test('其它 scheme 和解析不了的一律不安全', () {
      expect(isSecureAiEndpointUrl('ftp://example.com/x'), isFalse);
      expect(isSecureAiEndpointUrl('ws://localhost:1234'), isFalse);
      expect(isSecureAiEndpointUrl('api.openai.com/v1'), isFalse);
      expect(isSecureAiEndpointUrl(''), isFalse);
    });
  });
}
