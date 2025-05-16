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
    await _storage.setString(_apiKeyKey, key);
    debugPrint('API密钥已安全保存');
  }

  /// 获取API密钥
  Future<String?> getApiKey() async {
    await ensureInitialized();
    return _storage.getString(_apiKeyKey);
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