import 'secure_storage_service.dart';
import '../utils/app_logger.dart';

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
    logDebug('已保存供应商 $providerId 的API密钥');
  }

  /// 获取指定供应商的API密钥
  Future<String> getProviderApiKey(String providerId) async {
    try {
      final apiKey = await _secureStorage.getProviderApiKey(providerId);
      return apiKey?.trim() ?? '';
    } catch (e, stackTrace) {
      AppLogger.e(
        '获取供应商 $providerId 的API密钥失败',
        error: e,
        stackTrace: stackTrace,
        source: 'APIKeyManager',
      );
      return '';
    }
  }

  /// 检查指定供应商是否有有效的API密钥（仅从安全存储验证）
  Future<bool> hasValidProviderApiKey(String providerId) async {
    try {
      final apiKey = await getProviderApiKey(providerId);
      final isValid = apiKey.isNotEmpty && _isValidApiKeyFormat(apiKey);
      logDebug(
        '验证API Key - Provider: $providerId, '
        'HasKey: ${apiKey.isNotEmpty}, IsValidFormat: $isValid',
      );
      return isValid;
    } catch (e, stackTrace) {
      AppLogger.e(
        '验证API Key失败 - Provider: $providerId',
        error: e,
        stackTrace: stackTrace,
        source: 'APIKeyManager',
      );
      return false;
    }
  }

  /// 删除指定供应商的API密钥
  Future<void> removeProviderApiKey(String providerId) async {
    await _secureStorage.removeProviderApiKey(providerId);
    logDebug('已删除供应商 $providerId 的API密钥');
  }

  /// 验证API密钥格式（公共方法）
  bool isValidApiKeyFormat(String apiKey) {
    return _isValidApiKeyFormat(apiKey);
  }

  /// 密钥长度下限——低于这个长度基本只能是误粘贴或被截断的内容。
  static const int _minApiKeyLength = 8;

  /// 清理API密钥（移除空白字符，并剥掉用户可能粘贴进来的 `Bearer ` 前缀）
  ///
  /// 存储中统一保存裸 token：`AIProviderSettings.buildHeaders()` 会自行拼
  /// `Bearer `，把前缀一起存下来会得到 `Bearer Bearer xxx`。
  String _cleanApiKey(String apiKey) {
    final withoutBearer = _stripBearerPrefix(apiKey.trim());
    return withoutBearer.replaceAll(RegExp(r'\s+'), '');
  }

  /// 剥离大小写不敏感的 `Bearer ` 前缀。
  String _stripBearerPrefix(String key) {
    const prefix = 'bearer ';
    if (key.toLowerCase().startsWith(prefix)) {
      return key.substring(prefix.length).trim();
    }
    return key;
  }

  /// 密钥中是否含空白或控制字符——出现即说明粘贴时带进了换行或多余内容。
  bool _hasIllegalKeyChars(String key) {
    for (final codeUnit in key.codeUnits) {
      if (codeUnit <= 0x20 || codeUnit == 0x7f) {
        return true;
      }
    }
    return false;
  }

  /// 验证API密钥格式
  ///
  /// 只做「看起来像一把密钥」的基本体检，**不做服务商前缀白名单**：各服务商的
  /// 密钥格式差异极大（OpenAI `sk-…`、Gemini `AIza…`、智谱 `id.secret`、
  /// Ollama Cloud `hex.suffix`、API Ninjas 纯字母数字），前缀白名单会把合法密钥
  /// 判成非法，让依赖此校验的功能（每日提示、会话标题、卡片生成等）静默降级到
  /// 本地兜底。密钥真正是否可用由服务端响应决定。
  bool _isValidApiKeyFormat(String apiKey) {
    final key = _stripBearerPrefix(apiKey.trim());
    if (key.length < _minApiKeyLength) return false;
    return !_hasIllegalKeyChars(key);
  }
}
