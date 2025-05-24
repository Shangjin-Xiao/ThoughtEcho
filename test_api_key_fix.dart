// 测试API Key修复
// 此文件用于验证API Key保存和读取是否正确

import 'package:flutter/material.dart';
import 'lib/services/secure_storage_service.dart';
import 'lib/services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('=== API Key 修复验证测试 ===');
  
  try {
    // 测试安全存储服务
    final secureStorage = SecureStorageService();
    
    // 测试保存API Key
    const testApiKey = 'sk-test123456789';
    print('保存测试API Key: $testApiKey');
    await secureStorage.saveApiKey(testApiKey);
    
    // 测试读取API Key
    final retrievedKey = await secureStorage.getApiKey();
    print('读取到的API Key: $retrievedKey');
    
    // 验证一致性
    if (retrievedKey == testApiKey) {
      print('✅ API Key保存和读取测试通过');
    } else {
      print('❌ API Key保存和读取测试失败');
      print('期望: $testApiKey');
      print('实际: $retrievedKey');
    }
    
    // 清理测试数据
    await secureStorage.clearAll();
    print('✅ 测试数据已清理');
    
  } catch (e) {
    print('❌ 测试失败: $e');
  }
  
  print('=== 测试完成 ===');
}
