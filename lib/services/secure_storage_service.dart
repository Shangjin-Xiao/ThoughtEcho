import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  Completer<void>? _initCompleter;
  bool _initialized = false;

  @visibleForTesting
  static void resetForTesting() {
    _instance._initialized = false;
    _instance._initCompleter = null;
  }

  factory SecureStorageService() => _instance;

  SecureStorageService._internal();

  /// 初始化存储（带并发保护）
  Future<void> _initStorage() async {
    if (_initialized) return;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      // 1. 尝试迁移旧数据
      await _migrateLegacyData();

      _initialized = true;
      logDebug('安全存储服务初始化完成');
      _initCompleter!.complete();
    } catch (e) {
      logDebug('安全存储服务初始化失败: $e');
      _initCompleter!.completeError(e);
      _initCompleter = null; // 允许重试
    }
  }

  /// 迁移遗留的不安全数据
  Future<void> _migrateLegacyData() async {
    try {
      // 使用局部变量，避免保存冗余的字段
      final legacyStorage = SafeMMKV();
      await legacyStorage.initialize();

      final oldData = legacyStorage.getString(_providerApiKeysKey);

      if (oldData != null && oldData.isNotEmpty) {
        logDebug('发现遗留API密钥，准备迁移...');

        bool copySuccess = false;
        try {
          // 检查新存储中是否已有数据，避免覆盖
          final newData = await _storage.read(key: _providerApiKeysKey);
          if (newData == null) {
            await _storage.write(key: _providerApiKeysKey, value: oldData);
            logDebug('API密钥迁移成功');
            copySuccess = true;
          } else {
            logDebug('新存储已有数据，跳过迁移');
            // 如果跳过迁移，视为"成功"处理了数据（保留了新数据），可以删除旧数据
            copySuccess = true;
          }
        } catch (e) {
          logDebug('API密钥迁移(复制)失败: $e');
          // 复制失败时不设置 copySuccess，防止下方删除旧数据导致丢失
        }

        // 只有在数据成功转移或确认为多余时，才删除旧的不安全数据
        if (copySuccess) {
          try {
            await legacyStorage.remove(_providerApiKeysKey);
            logDebug('遗留不安全数据已清除');
          } catch (e) {
            // 这是一个严重的安全隐患，但不能让应用崩溃
            logDebug('CRITICAL: 删除遗留不安全数据失败! 密钥仍可能存在于 SafeMMKV 中: $e');
          }
        }
      }
    } catch (e) {
      logDebug('遗留数据检查失败: $e');
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

    try {
      final existingKeys = await _getAllApiKeys();
      existingKeys[providerId] = cleanedKey;

      await _storage.write(
        key: _providerApiKeysKey,
        value: _encodeApiKeysMap(existingKeys),
      );
      logDebug('已保存 Provider $providerId 的API密钥');
    } catch (e) {
      logDebug('保存API密钥失败: $e');
      rethrow;
    }
  }

  /// 获取指定供应商的API密钥
  Future<String?> getProviderApiKey(String providerId) async {
    await ensureInitialized();
    try {
      final allKeys = await _getAllApiKeys();
      final apiKey = allKeys[providerId];
      // 避免日志打印具体Key内容，只打印是否存在
      // logDebug('获取API Key - Provider: $providerId, Found: ${apiKey?.isNotEmpty ?? false}');
      return apiKey;
    } catch (e) {
      logDebug('获取API Key失败 - Provider: $providerId, Error: $e');
      return null;
    }
  }

  /// 删除指定供应商的API密钥
  Future<void> removeProviderApiKey(String providerId) async {
    await ensureInitialized();

    try {
      final existingKeys = await _getAllApiKeys();
      if (existingKeys.containsKey(providerId)) {
        existingKeys.remove(providerId);
        await _storage.write(
          key: _providerApiKeysKey,
          value: _encodeApiKeysMap(existingKeys),
        );
        logDebug('已删除 Provider $providerId 的API密钥');
      }
    } catch (e) {
      logDebug('删除API密钥失败: $e');
      rethrow;
    }
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
  /// 如果失败抛出异常，避免返回空对象导致数据覆盖
  String _encodeApiKeysMap(Map<String, String> apiKeysMap) {
    return json.encode(apiKeysMap);
  }

  /// 解码JSON字符串为API密钥映射
  Map<String, String> _decodeApiKeysMap(String jsonString) {
    final decoded = json.decode(jsonString);
    if (decoded is Map<String, dynamic>) {
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    }
    return <String, String>{};
  }
}
