// ignore_for_file: experimental_member_use

import 'package:sentry_sqflite/sentry_sqflite.dart';
import 'package:sqflite/sqflite.dart';

/// 为已打开的数据库实例启用 Sentry SQL 与事务性能追踪。
///
/// 不替换全局 [databaseFactory]，避免影响数据库路径和平台工厂。
Database enableSentryDatabaseTracing(Database database) {
  if (database is SentryDatabase) {
    return database;
  }
  return SentryDatabase(database);
}
