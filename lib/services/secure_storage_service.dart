import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/mmkv_adapter.dart';

/// 安全存储服务，专门用于存储多供应商API密钥
class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();
  static const String _providerApiKeysKey = 'provider_api_keys';
  late MMKVAdapter _storage;
  bool _initialized = false;

  factory SecureStorageService() => _instance;

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

  /// 保存指定供应商的API密钥
  Future<void> saveProviderApiKey(String providerId, String apiKey) async {
    await ensureInitialized();

    final cleanedKey = apiKey.trim();
    if (cleanedKey.isEmpty) {
      await removeProviderApiKey(providerId);
      return;
    }

    final existingKeys = await _getAllApiKeys();
    existingKeys[providerId] = cleanedKey;

    await _storage.setString(
      _providerApiKeysKey,
      _encodeApiKeysMap(existingKeys),
    );
    debugPrint('已保存 Provider $providerId 的API密钥');
  }

  /// 获取指定供应商的API密钥
  Future<String?> getProviderApiKey(String providerId) async {
    await ensureInitialized();
    try {
      final allKeys = await _getAllApiKeys();
      final apiKey = allKeys[providerId];
      debugPrint(
        '获取API Key - Provider: $providerId, Found: ${apiKey?.isNotEmpty ?? false}',
      );
      return apiKey;
    } catch (e) {
      debugPrint('获取API Key失败 - Provider: $providerId, Error: $e');
      return null;
    }
  }

  /// 删除指定供应商的API密钥
  Future<void> removeProviderApiKey(String providerId) async {
    await ensureInitialized();

    final existingKeys = await _getAllApiKeys();
    existingKeys.remove(providerId);

    await _storage.setString(
      _providerApiKeysKey,
      _encodeApiKeysMap(existingKeys),
    );
    debugPrint('已删除 Provider $providerId 的API密钥');
  }

  /// 获取所有供应商的API密钥映射
  Future<Map<String, String>> _getAllApiKeys() async {
    await ensureInitialized();
    final keysJson = _storage.getString(_providerApiKeysKey);

    if (keysJson == null || keysJson.isEmpty) {
      return <String, String>{};
    }

    try {
      return _decodeApiKeysMap(keysJson);
    } catch (e) {
      debugPrint('解析API密钥失败: $e');
      return <String, String>{};
    }
  }

  /// 编码API密钥映射为JSON字符串
  String _encodeApiKeysMap(Map<String, String> apiKeysMap) {
    try {
      return json.encode(apiKeysMap);
    } catch (e) {
      debugPrint('编码API密钥映射失败: $e');
      return '{}';
    }
  }

  /// 解码JSON字符串为API密钥映射
  Map<String, String> _decodeApiKeysMap(String jsonString) {
    try {
      final decoded = json.decode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((key, value) => MapEntry(key, value.toString()));
      }
      return <String, String>{};
    } catch (e) {
      debugPrint('解码API密钥映射失败: $e');
      return <String, String>{};
    }
  }
}
