import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import '../services/api_key_manager.dart';
import '../services/settings_service.dart';

/// API Key生命周期调试工具
/// 帮助追踪API Key在保存、切换、读取、请求整个生命周期中的状态
class ApiKeyDebugger {
  static Future<void> debugApiKeyLifecycle(
    SettingsService settingsService,
  ) async {
    if (!kDebugMode) return;

    debugPrint('=== 🔍 API Key 生命周期调试开始 ===');

    try {
      final apiKeyManager = APIKeyManager();
      final multiSettings = settingsService.multiAISettings;

      // 1. 检查当前设置状态
      debugPrint('📋 1. 当前设置状态');
      debugPrint('   总provider数量: ${multiSettings.providers.length}');
      debugPrint(
        '   当前provider: ${multiSettings.currentProvider?.name ?? "无"}',
      );
      debugPrint(
        '   当前provider ID: ${multiSettings.currentProvider?.id ?? "无"}',
      );

      if (multiSettings.currentProvider != null) {
        final currentProvider = multiSettings.currentProvider!;

        // 2. 检查配置文件中的API Key状态
        debugPrint('📄 2. 配置文件中的API Key状态');
        debugPrint(
          '   配置中的API Key: ${currentProvider.apiKey.isEmpty ? "空" : "${currentProvider.apiKey.length}字符"}',
        );
        debugPrint(
          '   配置中的API Key内容: ${currentProvider.apiKey.isEmpty ? "空" : currentProvider.apiKey.substring(0, math.min(20, currentProvider.apiKey.length))}...',
        );

        // 3. 检查加密存储中的API Key状态
        debugPrint('🔐 3. 加密存储中的API Key状态');
        final secureApiKey = await apiKeyManager.getProviderApiKey(
          currentProvider.id,
        );
        debugPrint(
          '   安全存储中的API Key: ${secureApiKey.isEmpty ? "空" : "${secureApiKey.length}字符"}',
        );
        debugPrint(
          '   安全存储中的API Key内容: ${secureApiKey.isEmpty ? "空" : secureApiKey.substring(0, math.min(20, secureApiKey.length))}...',
        );

        // 4. 检查有效性验证结果
        debugPrint('✅ 4. 有效性验证结果');
        final isValid = await apiKeyManager.hasValidProviderApiKey(
          currentProvider.id,
        );
        final isFormatValid = apiKeyManager.isValidApiKeyFormat(secureApiKey);
        debugPrint('   整体有效性: $isValid');
        debugPrint('   格式有效性: $isFormatValid');

        // 5. 模拟buildHeaders获取API Key
        debugPrint('🔧 5. 模拟buildHeaders获取API Key');
        final headers = currentProvider.buildHeaders();
        final authHeader =
            headers['Authorization'] ?? headers['x-api-key'] ?? '';
        if (authHeader.isNotEmpty) {
          final apiKeyFromHeader = authHeader
              .replaceAll('Bearer ', '')
              .replaceAll('x-api-key ', '');
          debugPrint(
            '   Headers中的API Key: ${apiKeyFromHeader.isEmpty ? "空" : "${apiKeyFromHeader.length}字符"}',
          );
          debugPrint(
            '   Headers中的API Key内容: ${apiKeyFromHeader.isEmpty ? "空" : apiKeyFromHeader.substring(0, math.min(20, apiKeyFromHeader.length))}...',
          );
          debugPrint(
            '   Headers与安全存储是否一致: ${apiKeyFromHeader == secureApiKey}',
          );
        } else {
          debugPrint('   Headers中没有找到API Key');
        }

        // 6. 检查所有providers的API Key状态
        debugPrint('📊 6. 所有providers的API Key状态');
        for (int i = 0; i < multiSettings.providers.length; i++) {
          final provider = multiSettings.providers[i];
          final providerApiKey = await apiKeyManager.getProviderApiKey(
            provider.id,
          );
          final isCurrentProvider = provider.id == currentProvider.id;
          debugPrint(
            '   Provider ${i + 1}: ${provider.name} ${isCurrentProvider ? "(当前)" : ""}',
          );
          debugPrint('     ID: ${provider.id}');
          debugPrint(
            '     配置中API Key: ${provider.apiKey.isEmpty ? "空" : "${provider.apiKey.length}字符"}',
          );
          debugPrint(
            '     安全存储API Key: ${providerApiKey.isEmpty ? "空" : "${providerApiKey.length}字符"}',
          );
          debugPrint(
            '     有效性: ${await apiKeyManager.hasValidProviderApiKey(provider.id)}',
          );
        }
      } else {
        debugPrint('⚠️ 未设置当前provider');
      }

      debugPrint('=== 🔍 API Key 生命周期调试完成 ===');
    } catch (e) {
      debugPrint('=== ❌ API Key 生命周期调试失败 ===');
      debugPrint('错误: $e');
    }
  }

  /// 调试API Key保存过程
  static Future<void> debugApiKeySave(String providerId, String apiKey) async {
    if (!kDebugMode) return;

    debugPrint('=== 💾 API Key 保存过程调试 ===');
    debugPrint('Provider ID: $providerId');
    debugPrint('API Key长度: ${apiKey.length}');
    debugPrint(
      'API Key前缀: ${apiKey.length > 20 ? apiKey.substring(0, 20) : apiKey}...',
    );

    try {
      final apiKeyManager = APIKeyManager();

      // 保存前检查
      final beforeSave = await apiKeyManager.getProviderApiKey(providerId);
      debugPrint(
        '保存前存储状态: ${beforeSave.isEmpty ? "空" : "${beforeSave.length}字符"}',
      );

      // 保存
      await apiKeyManager.saveProviderApiKey(providerId, apiKey);
      debugPrint('✅ 保存操作完成');

      // 保存后检查
      final afterSave = await apiKeyManager.getProviderApiKey(providerId);
      debugPrint(
        '保存后存储状态: ${afterSave.isEmpty ? "空" : "${afterSave.length}字符"}',
      );
      debugPrint('保存是否成功: ${afterSave == apiKey}');

      if (afterSave != apiKey) {
        debugPrint('❌ 保存验证失败！');
        debugPrint('期望: $apiKey');
        debugPrint('实际: $afterSave');
      }
    } catch (e) {
      debugPrint('❌ 保存过程出错: $e');
    }

    debugPrint('=== 💾 API Key 保存过程调试完成 ===');
  }

  /// 调试API Key在请求时的状态
  static Future<void> debugApiKeyInRequest(
    String providerId,
    String providerName,
    String apiKey,
  ) async {
    if (!kDebugMode) return;

    debugPrint('=== 🌐 API Key 请求时状态调试 ===');
    debugPrint('Provider ID: $providerId');
    debugPrint('Provider Name: $providerName');
    debugPrint('传入API Key长度: ${apiKey.length}');
    debugPrint('传入API Key是否为空: ${apiKey.isEmpty}');
    debugPrint(
      '传入API Key前缀: ${apiKey.length > 0 ? apiKey.substring(0, math.min(20, apiKey.length)) : "无"}',
    );

    try {
      final apiKeyManager = APIKeyManager();

      // 从加密存储读取API Key进行对比
      final storedApiKey = await apiKeyManager.getProviderApiKey(providerId);
      debugPrint('存储中的API Key长度: ${storedApiKey.length}');
      debugPrint('存储中的API Key是否为空: ${storedApiKey.isEmpty}');
      debugPrint(
        '存储中的API Key前缀: ${storedApiKey.length > 0 ? storedApiKey.substring(0, math.min(20, storedApiKey.length)) : "无"}',
      );

      // 比较传入的API Key和存储的API Key
      debugPrint('传入API Key与存储API Key是否一致: ${apiKey == storedApiKey}');

      // 检查格式有效性
      final isFormatValid = apiKeyManager.isValidApiKeyFormat(apiKey);
      debugPrint('传入API Key格式是否有效: $isFormatValid');

      // 检查整体有效性
      final isValid = await apiKeyManager.hasValidProviderApiKey(providerId);
      debugPrint('存储API Key整体有效性: $isValid');

      if (apiKey.isEmpty) {
        debugPrint('❌ 传入API Key为空！这是导致请求失败的原因');
      } else if (storedApiKey.isEmpty) {
        debugPrint('❌ 存储中的API Key为空！用户可能未正确保存');
      } else if (apiKey != storedApiKey) {
        debugPrint('❌ 传入API Key与存储API Key不一致！可能是加载失败');
      } else {
        debugPrint('✅ API Key状态正常');
      }
    } catch (e) {
      debugPrint('❌ 请求时API Key状态调试出错: $e');
    }

    debugPrint('=== 🌐 API Key 请求时状态调试完成 ===');
  }
}
