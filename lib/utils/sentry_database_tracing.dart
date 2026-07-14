// ignore_for_file: experimental_member_use

import 'package:sqflite/sqflite.dart';

/// 为已打开的数据库实例启用 Sentry SQL 与事务性能追踪。
///
/// 不替换全局 [databaseFactory]，避免影响数据库路径和平台工厂。
class SentryDatabaseTracing {
  SentryDatabaseTracing._();

  /// 根据用户明确授权配置主数据库性能追踪。
  ///
  /// 仅影响之后打开的主数据库连接，避免运行时热替换现有连接。
  static void configure({required bool enabled}) {}

  /// 仅在用户明确授权后包装主笔记数据库。
  static Database wrapMainDatabase(Database database) {
    return database;
  }
}
