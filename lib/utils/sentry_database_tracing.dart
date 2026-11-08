// ignore_for_file: experimental_member_use

import 'package:sentry_sqflite/sentry_sqflite.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 为已打开的数据库实例启用 Sentry SQL 与事务性能追踪。
///
/// 不替换全局 [databaseFactory]，避免影响数据库路径和平台工厂。
class SentryDatabaseTracing {
  SentryDatabaseTracing._();

  static bool _enabled = false;
  static final Expando<Database> _originalDatabases =
      Expando<Database>('sentry_original_databases');

  static bool get isEnabled => _enabled;

  /// 根据用户明确授权配置主数据库性能追踪。
  static void configure({required bool enabled}) {
    _enabled = enabled;
  }

  /// 仅在用户明确授权后包装主笔记数据库，并记录原始原生句柄。
  static Database wrapMainDatabase(Database database) {
    final isSentryDb = database is SentryDatabase;
    if (!_enabled || isSentryDb) {
      return database;
    }
    final wrapped = SentryDatabase(database);
    _originalDatabases[wrapped] = database;
    return wrapped;
  }

  /// 将 [SentryDatabase] 解包还原为原生 [Database] 句柄。
  static Database unwrapMainDatabase(Database database) {
    if (database is! SentryDatabase) {
      return database;
    }

    final original = _originalDatabases[database];
    if (original != null) {
      return original;
    }

    // 回退方案：通过 SentryDatabase 内部引用的原生 db 句柄进行解包
    try {
      // ignore: avoid_dynamic_calls
      final dynamic candidate = (database as dynamic).db;
      if (candidate is Database) {
        return candidate;
      }
    } catch (e) {
      logWarning(
        'Failed to unwrap SentryDatabase via fallback lookup: $e',
        source: 'SentryDatabaseTracing',
      );
    }

    return database;
  }
}
