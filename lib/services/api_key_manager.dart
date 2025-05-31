import 'package:flutter/foundation.dart';
import '../models/ai_settings.dart';
import 'secure_storage_service.dart';

/// 统一的API密钥管理器
///
/// 负责：
/// 1. 统一API密钥获取逻辑（优先安全存储，然后常规设置）
/// 2. 自动迁移API密钥到安全存储
/// 3. 密钥验证和清理
/// 4. 缓存机制以提高性能
class APIKeyManager {
  static final APIKeyManager _instance = APIKeyManager._internal();
  factory APIKeyManager() => _instance;
  APIKeyManager._internal();

  final SecureStorageService _secureStorage = SecureStorageService();

  // 缓存机制
  String? _cachedApiKey;
  DateTime? _cacheTime;
  static const Duration _cacheTimeout = Duration(minutes: 5);

  /// 获取有效的API密钥
  ///
  /// 优先级：
  /// 1. 安全存储中的密钥
  /// 2. 常规设置中的密钥（同时自动迁移到安全存储）
  ///
  /// 返回清理后的密钥，如果没有有效密钥则返回空字符串
  Future<String> getEffectiveApiKey(AISettings settings) async {
    try {
      // 检查缓存
      if (_isValidCache()) {
        return _cachedApiKey!;
      }

      await _secureStorage.ensureInitialized();
      String? secureApiKey = await _secureStorage.getApiKey();

      // 优先使用安全存储中的密钥
      if (secureApiKey != null && secureApiKey.trim().isNotEmpty) {
        final cleanedKey = _cleanApiKey(secureApiKey);
        _updateCache(cleanedKey);
        return cleanedKey;
      }

      // 如果安全存储中没有，检查常规设置
      if (settings.apiKey.trim().isNotEmpty) {
        final cleanedKey = _cleanApiKey(settings.apiKey);

        // 自动迁移到安全存储
        await _migrateApiKeyToSecure(cleanedKey);

        _updateCache(cleanedKey);
        return cleanedKey;
      }

      // 没有找到有效的密钥
      _updateCache('');
      return '';
    } catch (e) {
      debugPrint('获取API密钥失败: $e');
      return '';
    }
  }

  /// 检查是否有有效的API密钥
  Future<bool> hasValidApiKey(AISettings settings) async {
    final apiKey = await getEffectiveApiKey(settings);
    return apiKey.isNotEmpty && _isValidApiKeyFormat(apiKey);
  }

  /// 同步检查API密钥（仅用于UI快速判断）
  ///
  /// 注意：此方法使用缓存，如果缓存无效会返回false
  /// 对于准确的验证，请使用异步方法 hasValidApiKey()
  bool hasValidApiKeySync(AISettings settings) {
    // 检查缓存
    if (_isValidCache()) {
      return _cachedApiKey!.isNotEmpty && _isValidApiKeyFormat(_cachedApiKey!);
    }

    // 如果没有缓存，检查设置中的密钥作为快速判断
    return settings.apiKey.trim().isNotEmpty &&
        _isValidApiKeyFormat(settings.apiKey);
  }

  /// 保存API密钥到安全存储
  Future<void> saveApiKey(String apiKey) async {
    final cleanedKey = _cleanApiKey(apiKey);
    await _secureStorage.ensureInitialized();
    await _secureStorage.saveApiKey(cleanedKey);
    _updateCache(cleanedKey);
  }

  /// 从AISettings保存API密钥
  ///
  /// 如果settings中包含API密钥，将其保存到安全存储
  /// 这是一个便利方法，专门用于处理AISettings的API密钥更新
  Future<void> saveApiKeyFromSettings(AISettings settings) async {
    if (settings.apiKey.trim().isNotEmpty) {
      await saveApiKey(settings.apiKey);
      debugPrint('API密钥已从设置保存到安全存储');
    }
  }

  /// 清除API密钥缓存
  void clearCache() {
    _cachedApiKey = null;
    _cacheTime = null;
  }

  /// 清除所有API密钥数据
  ///
  /// 清除安全存储中的API密钥和缓存
  Future<void> clearApiKey() async {
    await _secureStorage.ensureInitialized();
    await _secureStorage.clearAll();
    clearCache();
    debugPrint('API密钥已从安全存储和缓存中清除');
  }

  /// 验证API密钥格式
  bool _isValidApiKeyFormat(String apiKey) {
    if (apiKey.trim().isEmpty) return false;

    // 检查常见的API密钥格式
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

  /// 清理API密钥（移除空格、换行符等）
  String _cleanApiKey(String apiKey) {
    String cleaned = apiKey.trim();

    // 移除换行符和回车符
    cleaned = cleaned.replaceAll('\n', '').replaceAll('\r', '');

    // 记录清理操作
    if (cleaned != apiKey) {
      debugPrint('API密钥已清理：移除了空格、换行符等无效字符');
    }

    return cleaned;
  }

  /// 自动迁移API密钥到安全存储
  Future<void> _migrateApiKeyToSecure(String apiKey) async {
    try {
      await _secureStorage.saveApiKey(apiKey);
      debugPrint('API密钥已自动迁移到安全存储');
    } catch (e) {
      debugPrint('迁移API密钥到安全存储失败: $e');
    }
  }

  /// 检查缓存是否有效
  bool _isValidCache() {
    if (_cachedApiKey == null || _cacheTime == null) return false;

    final now = DateTime.now();
    return now.difference(_cacheTime!) < _cacheTimeout;
  }

  /// 更新缓存
  void _updateCache(String apiKey) {
    _cachedApiKey = apiKey;
    _cacheTime = DateTime.now();
  }

  /// 获取API密钥诊断信息
  Future<Map<String, dynamic>> getDiagnosticInfo(AISettings settings) async {
    await _secureStorage.ensureInitialized();
    final secureApiKey = await _secureStorage.getApiKey();
    final settingsApiKey = settings.apiKey;
    final effectiveKey = await getEffectiveApiKey(settings);

    return {
      'secureStorage': {
        'hasKey': secureApiKey != null && secureApiKey.isNotEmpty,
        'keyLength': secureApiKey?.length ?? 0,
        'keyPrefix':
            secureApiKey != null && secureApiKey.length > 15
                ? secureApiKey.substring(0, 15) + '...'
                : secureApiKey ?? '',
        'hasNewlines':
            secureApiKey?.contains('\n') == true ||
            secureApiKey?.contains('\r') == true,
        'hasSpaces':
            secureApiKey?.startsWith(' ') == true ||
            secureApiKey?.endsWith(' ') == true,
      },
      'settings': {
        'hasKey': settingsApiKey.isNotEmpty,
        'keyLength': settingsApiKey.length,
        'keyPrefix':
            settingsApiKey.length > 15
                ? settingsApiKey.substring(0, 15) + '...'
                : settingsApiKey,
        'hasNewlines':
            settingsApiKey.contains('\n') || settingsApiKey.contains('\r'),
        'hasSpaces':
            settingsApiKey.startsWith(' ') || settingsApiKey.endsWith(' '),
      },
      'effective': {
        'hasKey': effectiveKey.isNotEmpty,
        'keyLength': effectiveKey.length,
        'source':
            secureApiKey != null && secureApiKey.isNotEmpty
                ? 'secureStorage'
                : 'settings',
        'isValid': _isValidApiKeyFormat(effectiveKey),
        'format': _detectApiKeyFormat(effectiveKey),
      },
      'cache': {
        'hasCachedKey': _cachedApiKey != null,
        'isValid': _isValidCache(),
        'cacheTime': _cacheTime?.toIso8601String(),
      },
    };
  }

  /// 检测API密钥格式
  String _detectApiKeyFormat(String apiKey) {
    if (apiKey.isEmpty) return 'empty';

    final trimmed = apiKey.trim();
    if (trimmed.startsWith('sk-')) return 'OpenAI';
    if (trimmed.startsWith('sk_')) return 'OpenRouter (sk_)';
    if (trimmed.startsWith('or_')) return 'OpenRouter (or_)';
    if (trimmed.startsWith('Bearer ')) return 'Bearer Token';
    if (trimmed.startsWith('AIzaSy')) return 'Google AI';
    if (trimmed.startsWith('ANTHROPIC_')) return 'Anthropic';

    return 'Custom/Unknown';
  }
}
