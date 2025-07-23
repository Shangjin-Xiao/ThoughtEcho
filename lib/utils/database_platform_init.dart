import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app_logger.dart';

/// 数据库平台初始化工具类
/// 确保FFI只初始化一次，避免Windows平台启动卡死问题
class DatabasePlatformInit {
  static bool _isInitialized = false;

  /// 初始化数据库平台支持
  /// 在Windows平台下配置FFI，其他平台使用默认配置
  static void initialize() {
    if (_isInitialized) {
      logDebug('数据库平台已初始化，跳过重复初始化', source: 'DatabasePlatformInit');
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      try {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        logInfo('Windows平台FFI数据库工厂初始化成功', source: 'DatabasePlatformInit');
      } catch (e) {
        logError('Windows平台FFI初始化失败: $e',
            error: e, source: 'DatabasePlatformInit');
        rethrow;
      }
    }

    _isInitialized = true;
  }

  /// 检查是否已初始化
  static bool get isInitialized => _isInitialized;

  /// 重置初始化状态（仅用于测试）
  @visibleForTesting
  static void resetForTesting() {
    _isInitialized = false;
  }
}
