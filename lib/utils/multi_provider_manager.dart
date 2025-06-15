import '../models/ai_provider_settings.dart';
import '../models/multi_ai_settings.dart';
import '../services/settings_service.dart';
import '../services/api_key_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 多provider设置管理器
class MultiProviderManager {
  static Future<void> initializeDefaultProviders(
    SettingsService settingsService,
  ) async {
    logDebug('初始化默认AI服务商配置...');

    try {
      // 获取当前设置
      final currentMultiSettings = settingsService.multiAISettings;

      // 如果已经有配置，则不重复初始化
      if (currentMultiSettings.providers.isNotEmpty) {
        logDebug('已存在provider配置，跳过初始化');
        return;
      }

      // 创建默认的多provider设置
      final defaultSettings = MultiAISettings.defaultSettings();

      // 保存到设置服务
      await settingsService.saveMultiAISettings(defaultSettings);

      logDebug('默认AI服务商配置初始化完成');
      logDebug(
        '已配置的服务商: ${defaultSettings.providers.map((p) => p.name).join(', ')}',
      );
    } catch (e) {
      logDebug('初始化默认provider配置失败: $e');
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
      final providerIndex = currentSettings.providers.indexWhere(
        (p) => p.id == providerId,
      );
      if (providerIndex == -1) {
        logDebug('未找到provider: $providerId');
        return;
      }

      // 保存API密钥到安全存储
      final apiKeyManager = APIKeyManager();
      if (apiKey.trim().isNotEmpty) {
        await apiKeyManager.saveProviderApiKey(providerId, apiKey);
        logDebug('已保存 $providerId 的API密钥到安全存储');
      } else {
        await apiKeyManager.removeProviderApiKey(providerId);
        logDebug('已删除 $providerId 的API密钥');
      }

      // 更新provider设置
      final updatedProviders = List<AIProviderSettings>.from(
        currentSettings.providers,
      );
      updatedProviders[providerIndex] = updatedProviders[providerIndex]
          .copyWith(apiKey: apiKey, isEnabled: apiKey.isNotEmpty);

      // 更新设置
      final updatedSettings = currentSettings.copyWith(
        providers: updatedProviders,
      );
      await settingsService.saveMultiAISettings(updatedSettings);

      logDebug('Provider $providerId 配置成功');
    } catch (e) {
      logDebug('配置provider失败: $e');
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
      final updatedSettings = currentSettings.copyWith(
        currentProviderId: providerId,
      );
      await settingsService.saveMultiAISettings(updatedSettings);

      logDebug('当前provider已切换到: ${provider.name}');
    } catch (e) {
      logDebug('切换provider失败: $e');
    }
  }

  static List<AIProviderSettings> getAvailableProviders(
    SettingsService settingsService,
  ) {
    return settingsService.multiAISettings.availableProviders;
  }

  static AIProviderSettings? getCurrentProvider(
    SettingsService settingsService,
  ) {
    return settingsService.multiAISettings.currentProvider;
  }

  /// 获取当前供应商的有效API密钥（从安全存储获取）
  static Future<String> getCurrentProviderApiKey(
    SettingsService settingsService,
  ) async {
    try {
      final currentProvider = settingsService.multiAISettings.currentProvider;
      if (currentProvider == null) {
        return '';
      }

      final apiKeyManager = APIKeyManager();
      return await apiKeyManager.getProviderApiKey(currentProvider.id);
    } catch (e) {
      logDebug('获取当前供应商API密钥失败: $e');
      return '';
    }
  }
}
