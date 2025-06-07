// Test file to verify AI Service API key saving logic
// This is a manual test - run in debug mode to see results

import 'package:flutter/foundation.dart';
import '../services/api_key_manager.dart';
import '../models/ai_provider_settings.dart';

class ApiKeySaveLogicTest {
  static Future<void> runTest() async {
    if (!kDebugMode) return;
    
    debugPrint('=== API密钥保存逻辑测试开始 ===');
    
    try {
      // 1. 测试多供应商API密钥保存
      final apiKeyManager = APIKeyManager();
      const testProviderId = 'test_openrouter';
      const testApiKey = 'sk_test123456789012345678901234567890';

      debugPrint('1. 测试多供应商API密钥保存...');
      await apiKeyManager.saveProviderApiKey(testProviderId, testApiKey);

      // 2. 测试从安全存储获取
      final retrievedKey = await apiKeyManager.getProviderApiKey(testProviderId);
      debugPrint('2. 从安全存储获取的密钥: ${retrievedKey.isNotEmpty ? "${retrievedKey.substring(0, 10)}..." : "空"}');

      // 3. 测试有效性检查
      final isValid = await apiKeyManager.hasValidProviderApiKey(testProviderId);
      debugPrint('3. API密钥有效性: $isValid');

      // 4. 测试同步检查
      const testProvider = AIProviderSettings(
        id: testProviderId,
        name: 'Test Provider',
        apiKey: testApiKey,
        apiUrl: 'https://test.com',
        model: 'test-model',
      );
      final isSyncValid = apiKeyManager.hasValidProviderApiKeySync(testProvider);
      debugPrint('4. 同步有效性检查: $isSyncValid');

      // 5. 测试格式验证
      final isFormatValid = apiKeyManager.isValidApiKeyFormat(testApiKey);
      debugPrint('5. 格式验证: $isFormatValid');

      // 6. 清理测试数据
      await apiKeyManager.removeProviderApiKey(testProviderId);
      debugPrint('6. 测试数据已清理');
      
      debugPrint('=== API密钥保存逻辑测试完成 ===');
      
    } catch (e) {
      debugPrint('=== 测试失败: $e ===');
    }
  }
}
