import 'package:flutter/foundation.dart';
import '../models/ai_provider_settings.dart';
import 'secure_storage_service.dart';

/// 多供应商API密钥管理器
class APIKeyManager {
  static final APIKeyManager _instance = APIKeyManager._internal();
  factory APIKeyManager() => _instance;
  APIKeyManager._internal();

  final SecureStorageService _secureStorage = SecureStorageService();

  /// 保存指定供应商的API密钥
  Future<void> saveProviderApiKey(String providerId, String apiKey) async {
    final cleanedKey = _cleanApiKey(apiKey);
    await _secureStorage.saveProviderApiKey(providerId, cleanedKey);
    debugPrint('已保存供应商 $providerId 的API密钥');
  }

  /// 获取指定供应商的API密钥
  Future<String> getProviderApiKey(String providerId) async {
    try {
      final apiKey = await _secureStorage.getProviderApiKey(providerId);
      return apiKey?.trim() ?? '';
    } catch (e) {
      debugPrint('获取供应商 $providerId 的API密钥失败: $e');
      return '';
    }
  }

  /// 检查指定供应商是否有有效的API密钥（从安全存储验证）
  Future<bool> hasValidProviderApiKey(String providerId) async {
    try {
      final apiKey = await getProviderApiKey(providerId);
      final isValid = apiKey.isNotEmpty && _isValidApiKeyFormat(apiKey);
      debugPrint('异步验证API Key - Provider: $providerId, '
          'HasKey: ${apiKey.isNotEmpty}, IsValidFormat: $isValid');
      return isValid;
    } catch (e) {
      debugPrint('异步验证API Key失败 - Provider: $providerId, Error: $e');
      return false;
    }
  }

  /// 同步检查指定供应商的API密钥（用于UI快速判断）
  bool hasValidProviderApiKeySync(AIProviderSettings provider) {
    return provider.apiKey.trim().isNotEmpty && _isValidApiKeyFormat(provider.apiKey);
  }

  /// 删除指定供应商的API密钥
  Future<void> removeProviderApiKey(String providerId) async {
    await _secureStorage.removeProviderApiKey(providerId);
    debugPrint('已删除供应商 $providerId 的API密钥');
  }

  /// 验证API密钥格式（公共方法）
  bool isValidApiKeyFormat(String apiKey) {
    return _isValidApiKeyFormat(apiKey);
  }

  /// 清理API密钥（移除空格和换行符）
  String _cleanApiKey(String apiKey) {
    return apiKey.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// 验证API密钥格式
  bool _isValidApiKeyFormat(String apiKey) {
    if (apiKey.trim().isEmpty) return false;

    final trimmedKey = apiKey.trim();

    // OpenAI格式: sk-...
    if (trimmedKey.startsWith('sk-') && trimmedKey.length > 20) {
      return true;
    }

    // OpenRouter格式: sk_... 或 or_...
    if ((trimmedKey.startsWith('sk_') || trimmedKey.startsWith('or_')) &&
        trimmedKey.length > 20) {
      return true;
    }

    // Bearer token格式
    if (trimmedKey.startsWith('Bearer ') && trimmedKey.length > 20) {
      return true;
    }

    // 其他格式，基本长度检查
    if (trimmedKey.length >= 20) {
      return true;
    }

    return false;
  }
}
