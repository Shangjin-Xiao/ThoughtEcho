// Test file to verify AI Service API key saving logic
// This is a manual test - run in debug mode to see results

import 'package:flutter/foundation.dart';
import '../services/api_key_manager.dart';
import '../models/ai_settings.dart';

class ApiKeySaveLogicTest {
  static Future<void> runTest() async {
    if (!kDebugMode) return;
    
    debugPrint('=== API密钥保存逻辑测试开始 ===');
    
    try {
      // 1. 测试APIKeyManager直接保存
      final apiKeyManager = APIKeyManager();
      const testApiKey = 'sk-test123456789012345678901234567890';
      
      debugPrint('1. 测试APIKeyManager直接保存...');
      await apiKeyManager.saveApiKey(testApiKey);
      
      // 2. 测试从AISettings获取
      final testSettings = AISettings(
        apiKey: '', // 空的，应该从安全存储获取
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-3.5-turbo',
      );
      
      final retrievedKey = await apiKeyManager.getEffectiveApiKey(testSettings);
      debugPrint('2. 从安全存储获取的密钥: ${retrievedKey.substring(0, 10)}...');
      
      // 3. 测试有效性检查
      final isValid = await apiKeyManager.hasValidApiKey(testSettings);
      debugPrint('3. API密钥有效性: $isValid');
      
      // 4. 测试同步检查
      final isSyncValid = apiKeyManager.hasValidApiKeySync(testSettings);
      debugPrint('4. 同步有效性检查: $isSyncValid');
      
      // 5. 测试诊断信息
      final diagnostics = await apiKeyManager.getDiagnosticInfo(testSettings);
      debugPrint('5. 诊断信息:');
      debugPrint('   - 安全存储有密钥: ${diagnostics['secureStorage']['hasKey']}');
      debugPrint('   - 设置有密钥: ${diagnostics['settings']['hasKey']}');
      debugPrint('   - 有效来源: ${diagnostics['effective']['source']}');
      debugPrint('   - 格式检测: ${diagnostics['effective']['format']}');
      
      // 6. 清理测试数据
      await apiKeyManager.clearApiKey();
      debugPrint('6. 测试数据已清理');
      
      debugPrint('=== API密钥保存逻辑测试完成 ===');
      
    } catch (e) {
      debugPrint('=== 测试失败: $e ===');
    }
  }
}
