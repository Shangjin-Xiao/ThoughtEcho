import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/mmkv_ffi_fix.dart'; // 保留引用用于迁移
import 'package:thoughtecho/utils/app_logger.dart';

/// 安全存储服务，专门用于存储多供应商API密钥
class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();
  static const String _providerApiKeysKey = 'provider_api_keys';

  // 使用 FlutterSecureStorage 替代 SafeMMKV
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // 仅用于迁移旧数据
  final SafeMMKV _legacyStorage = SafeMMKV();

  bool _initialized = false;

  factory SecureStorageService() => _instance;

  SecureStorageService._internal() {
    _initStorage();
  }

  Future<void> _initStorage() async {
    if (!_initialized) {
      // 尝试迁移旧数据
      try {
        await _legacyStorage.initialize();
        final oldData = _legacyStorage.getString(_providerApiKeysKey);

        if (oldData != null && oldData.isNotEmpty) {
          logDebug('正在迁移API密钥到安全存储...');
          // 检查新存储中是否已有数据，避免覆盖
          final newData = await _storage.read(key: _providerApiKeysKey);
          if (newData == null) {
            await _storage.write(key: _providerApiKeysKey, value: oldData);
            logDebug('API密钥迁移成功');
          } else {
            logDebug('新存储已有数据，跳过迁移');
          }
          // 无论是否迁移，都移除旧的不安全数据
          await _legacyStorage.remove(_providerApiKeysKey);
        }
      } catch (e) {
        logDebug('API密钥迁移检查失败: $e');
      }

      _initialized = true;
      logDebug('安全存储服务初始化完成');
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

    await _storage.write(
      key: _providerApiKeysKey,
      value: _encodeApiKeysMap(existingKeys),
    );
    logDebug('已保存 Provider $providerId 的API密钥');
  }

  /// 获取指定供应商的API密钥
  Future<String?> getProviderApiKey(String providerId) async {
    await ensureInitialized();
    try {
      final allKeys = await _getAllApiKeys();
      final apiKey = allKeys[providerId];
      logDebug(
        '获取API Key - Provider: $providerId, Found: ${apiKey?.isNotEmpty ?? false}',
      );
      return apiKey;
    } catch (e) {
      logDebug('获取API Key失败 - Provider: $providerId, Error: $e');
      return null;
    }
  }

  /// 删除指定供应商的API密钥
  Future<void> removeProviderApiKey(String providerId) async {
    await ensureInitialized();

    final existingKeys = await _getAllApiKeys();
    existingKeys.remove(providerId);

    await _storage.write(
      key: _providerApiKeysKey,
      value: _encodeApiKeysMap(existingKeys),
    );
    logDebug('已删除 Provider $providerId 的API密钥');
  }

  /// 获取所有供应商的API密钥映射
  Future<Map<String, String>> _getAllApiKeys() async {
    await ensureInitialized();
    final keysJson = await _storage.read(key: _providerApiKeysKey);

    if (keysJson == null || keysJson.isEmpty) {
      return <String, String>{};
    }

    try {
      return _decodeApiKeysMap(keysJson);
    } catch (e) {
      logDebug('解析API密钥失败: $e');
      return <String, String>{};
    }
  }

  /// 编码API密钥映射为JSON字符串
  String _encodeApiKeysMap(Map<String, String> apiKeysMap) {
    try {
      return json.encode(apiKeysMap);
    } catch (e) {
      logDebug('编码API密钥映射失败: $e');
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
      logDebug('解码API密钥映射失败: $e');
      return <String, String>{};
    }
  }
}
