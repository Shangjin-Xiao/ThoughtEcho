import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();
  late final FlutterSecureStorage _storage;

  // 安全存储的键名
  static const String _apiKeyKey = 'api_key_secure';

  factory SecureStorageService() {
    return _instance;
  }

  SecureStorageService._internal() {
    // 配置安全存储选项
    const AndroidOptions androidOptions = AndroidOptions(
      encryptedSharedPreferences: true,
    );

    const IOSOptions iosOptions = IOSOptions(accountName: 'thoughtecho_secure');

    _storage = const FlutterSecureStorage(
      aOptions: androidOptions,
      iOptions: iosOptions,
    );
  }

  /// 安全存储API密钥
  Future<void> saveApiKey(String apiKey) async {
    if (kIsWeb) {
      debugPrint('Web平台不支持安全存储，跳过存储操作');
      return;
    }

    await _storage.write(key: _apiKeyKey, value: apiKey);
  }

  /// 获取安全存储的API密钥
  Future<String?> getApiKey() async {
    if (kIsWeb) {
      debugPrint('Web平台不支持安全存储，返回空值');
      return null;
    }

    return await _storage.read(key: _apiKeyKey);
  }

  /// 删除安全存储的API密钥
  Future<void> deleteApiKey() async {
    if (kIsWeb) {
      debugPrint('Web平台不支持安全存储，跳过删除操作');
      return;
    }

    await _storage.delete(key: _apiKeyKey);
  }

  /// 检查是否存在安全存储的API密钥
  Future<bool> hasApiKey() async {
    if (kIsWeb) {
      debugPrint('Web平台不支持安全存储，返回false');
      return false;
    }

    final value = await _storage.read(key: _apiKeyKey);
    return value != null && value.isNotEmpty;
  }
}
