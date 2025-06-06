import 'package:flutter/material.dart';
import '../models/ai_provider_settings.dart';
import '../models/multi_ai_settings.dart';
import '../services/settings_service.dart';

/// 多provider设置管理器
class MultiProviderManager {
  static Future<void> initializeDefaultProviders(SettingsService settingsService) async {
    debugPrint('初始化默认AI服务商配置...');
    
    try {
      // 获取当前设置
      final currentMultiSettings = settingsService.multiAISettings;
      
      // 如果已经有配置，则不重复初始化
      if (currentMultiSettings.providers.isNotEmpty) {
        debugPrint('已存在provider配置，跳过初始化');
        return;
      }
      
      // 创建默认的多provider设置
      final defaultSettings = MultiAISettings.defaultSettings();
      
      // 保存到设置服务
      await settingsService.saveMultiAISettings(defaultSettings);
      
      debugPrint('默认AI服务商配置初始化完成');
      debugPrint('已配置的服务商: ${defaultSettings.providers.map((p) => p.name).join(', ')}');
      
    } catch (e) {
      debugPrint('初始化默认provider配置失败: $e');
    }
  }
  
  static Future<void> configureProvider(
    SettingsService settingsService,
    String providerId,
    String apiKey,
  ) async {
    try {
      final currentSettings = settingsService.multiAISettings;
      
      // 查找对应的provider
      final providerIndex = currentSettings.providers.indexWhere((p) => p.id == providerId);
      if (providerIndex == -1) {
        debugPrint('未找到provider: $providerId');
        return;
      }
      
      // 更新API密钥
      final updatedProviders = List<AIProviderSettings>.from(currentSettings.providers);
      updatedProviders[providerIndex] = updatedProviders[providerIndex].copyWith(
        apiKey: apiKey,
        isEnabled: apiKey.isNotEmpty,
      );
      
      // 更新设置
      final updatedSettings = currentSettings.copyWith(providers: updatedProviders);
      await settingsService.saveMultiAISettings(updatedSettings);
      
      debugPrint('Provider $providerId 配置成功');
    } catch (e) {
      debugPrint('配置provider失败: $e');
    }
  }
  
  static Future<void> setCurrentProvider(
    SettingsService settingsService,
    String providerId,
  ) async {
    try {
      final currentSettings = settingsService.multiAISettings;
      
      // 查找对应的provider
      final provider = currentSettings.providers.firstWhere(
        (p) => p.id == providerId,
        orElse: () => throw Exception('未找到provider: $providerId'),
      );
      
      // 更新当前provider
      final updatedSettings = currentSettings.copyWith(currentProviderId: providerId);
      await settingsService.saveMultiAISettings(updatedSettings);
      
      debugPrint('当前provider已切换到: ${provider.name}');
    } catch (e) {
      debugPrint('切换provider失败: $e');
    }
  }
  
  static List<AIProviderSettings> getAvailableProviders(SettingsService settingsService) {
    return settingsService.multiAISettings.availableProviders;
  }
  
  static AIProviderSettings? getCurrentProvider(SettingsService settingsService) {
    return settingsService.multiAISettings.currentProvider;
  }
}
