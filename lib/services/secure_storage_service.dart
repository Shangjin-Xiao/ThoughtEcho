import 'package:flutter/foundation.dart';
import '../utils/mmkv_adapter.dart';

/// 安全存储服务，用于存储敏感信息如API密钥
class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  static const String _apiKeyKey = 'secure_api_key';
  static const String _apiUrlKey = 'secure_api_url';
  late MMKVAdapter _storage;
  bool _initialized = false;

  factory SecureStorageService() {
    return _instance;
  }

  SecureStorageService._internal() {
    _initStorage();
  }

  Future<void> _initStorage() async {
    if (!_initialized) {
      _storage = MMKVAdapter();
      await _storage.initialize();
      _initialized = true;
      debugPrint('安全存储服务初始化完成');
    }
  }

  /// 确保存储已初始化
  Future<void> ensureInitialized() async {
    if (!_initialized) {
      await _initStorage();
    }
  }
  /// 保存API密钥
  Future<void> saveApiKey(String key) async {
    await ensureInitialized();
    
    // 添加调试信息
    debugPrint('=== 保存API密钥调试信息 ===');
    debugPrint('原始密钥长度: ${key.length}');
    debugPrint('密钥前缀: ${key.length > 10 ? key.substring(0, 10) : key}...');
    
    // 清理密钥（移除可能的空格和换行符）
    final cleanedKey = key.trim();
    debugPrint('清理后密钥长度: ${cleanedKey.length}');
    
    if (cleanedKey != key) {
      debugPrint('警告: 密钥已被清理，移除了前后空格或换行符');
    }
    
    await _storage.setString(_apiKeyKey, cleanedKey);
    debugPrint('API密钥已安全保存');
    debugPrint('========================');
  }
  /// 获取API密钥
  Future<String?> getApiKey() async {
    await ensureInitialized();
    final key = _storage.getString(_apiKeyKey);
    
    // 添加调试信息
    debugPrint('=== 获取API密钥调试信息 ===');
    debugPrint('存储中的密钥: ${key != null ? "存在 (长度: ${key.length})" : "不存在"}');
    
    if (key != null) {
      debugPrint('密钥前缀: ${key.length > 10 ? key.substring(0, 10) : key}...');
      
      // 检查密钥完整性
      if (key.contains('\n') || key.contains('\r')) {
        debugPrint('警告: 存储的API密钥包含换行符！');
      }
      if (key.startsWith(' ') || key.endsWith(' ')) {
        debugPrint('警告: 存储的API密钥包含前后空格！');
      }
    }
    debugPrint('========================');
    
    return key;
  }

  /// 保存API URL
  Future<void> saveApiUrl(String url) async {
    await ensureInitialized();
    await _storage.setString(_apiUrlKey, url);
  }

  /// 获取API URL
  Future<String?> getApiUrl() async {
    await ensureInitialized();
    return _storage.getString(_apiUrlKey);
  }

  /// 清除所有安全存储的数据
  Future<void> clearAll() async {
    await ensureInitialized();
    await _storage.clear();
    debugPrint('所有安全存储的数据已清除');
  }
} 