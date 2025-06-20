// Test file to verify AI Service API key saving logic
// This is a manual test - run in debug mode to see results

import 'package:flutter/foundation.dart';
import '../services/api_key_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class ApiKeySaveLogicTest {
  static Future<void> runTest() async {
    if (!kDebugMode) return;

    logDebug('=== API密钥保存逻辑测试开始 ===');

    try {
      final apiKeyManager = APIKeyManager();
      const testProviderId = 'test_openrouter';
      const testApiKey = 'sk_test123456789012345678901234567890';

      // 1. 测试API密钥保存
      logDebug('1. 测试API密钥保存...');
      await apiKeyManager.saveProviderApiKey(testProviderId, testApiKey);

      // 2. 测试从安全存储获取
      final retrievedKey = await apiKeyManager.getProviderApiKey(
        testProviderId,
      );
      logDebug(
        '2. 从安全存储获取的密钥: ${retrievedKey.isNotEmpty ? "${retrievedKey.substring(0, 10)}..." : "空"}',
      );

      // 验证保存和读取一致性
      final isConsistent = retrievedKey == testApiKey;
      logDebug('   保存读取一致性: ${isConsistent ? "✅" : "❌"}');

      // 3. 测试有效性检查
      final isValid = await apiKeyManager.hasValidProviderApiKey(
        testProviderId,
      );
      logDebug('3. API密钥有效性: ${isValid ? "✅" : "❌"}');

      // 4. 测试格式验证
      final isFormatValid = apiKeyManager.isValidApiKeyFormat(testApiKey);
      logDebug('4. 格式验证: ${isFormatValid ? "✅" : "❌"}');

      // 5. 清理测试数据
      await apiKeyManager.removeProviderApiKey(testProviderId);
      logDebug('5. 测试数据已清理');

      logDebug('=== API密钥保存逻辑测试完成 ✅ ===');
    } catch (e) {
      logDebug('=== API密钥保存逻辑测试失败 ❌ ===');
      logDebug('错误: $e');
    }
  }
}
