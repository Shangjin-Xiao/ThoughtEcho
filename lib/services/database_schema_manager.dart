import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/quote_model.dart';
import '../services/weather_service.dart';
import '../utils/app_logger.dart';
import '../utils/time_utils.dart';

part 'database/schema_definitions.dart';
part 'database/schema_lifecycle.dart';
part 'database/schema_repair_adapter.dart';
part 'database/schema_version_adapters.dart';

/// The single public entry point for the main notes database schema lifecycle.
///
/// It deliberately contains no migration SQL. The lifecycle coordinates schema
/// creation, ordered version adapters, repair, validation and data backfills so
/// every old-to-current path follows the same failure policy.
class DatabaseSchemaManager {
  DatabaseSchemaManager({DatabaseSchemaLifecycle? lifecycle})
      : _lifecycle = lifecycle ?? DatabaseSchemaLifecycle.standard();

  static const int schemaVersion = DatabaseSchemaDefinitions.schemaVersion;

  @visibleForTesting
  static const Set<String> requiredTablesForValidation =
      DatabaseSchemaDefinitions.requiredTables;

  final DatabaseSchemaLifecycle _lifecycle;

  @visibleForTesting
  static String poiNameSelectExpressionFromTableInfo(
    List<Map<String, Object?>> tableInfo,
  ) {
    final hasPoiNameColumn = tableInfo.any(
        (column) => column['name'] == DatabaseSchemaDefinitions.poiNameColumn);
    return hasPoiNameColumn
        ? DatabaseSchemaDefinitions.poiNameColumn
        : 'NULL AS ${DatabaseSchemaDefinitions.poiNameColumn}';
  }

  Future<void> createTables(Database database) =>
      _lifecycle.createCurrentSchema(database);

  Future<void> upgradeDatabase(
    Database database,
    int oldVersion,
    int newVersion,
  ) =>
      _lifecycle.upgrade(database, oldVersion, newVersion);

  Future<void> checkAndFixDatabaseStructure(Database database) =>
      _lifecycle.repair(database);

  Future<void> validateSchema(Database database) =>
      _lifecycle.validate(database);

  Future<void> performAllDataMigrations(Database? database) =>
      _lifecycle.backfill(database);

  Future<void> patchQuotesDayPeriod(Database? database) =>
      _lifecycle.patchQuotesDayPeriod(database);

  Future<void> migrateDayPeriodToKey(Database? database) =>
      _lifecycle.migrateDayPeriodToKey(database);

  Future<void> migrateWeatherToKey(
    Database? database, {
    List<Quote> memoryStore = const <Quote>[],
  }) =>
      _lifecycle.migrateWeatherToKey(database, memoryStore: memoryStore);

  Future<void> cleanupLegacyTagIdsColumn(Database database) =>
      _lifecycle.cleanupLegacyTagIdsColumn(database);

  Future<void> verifyForeignKeysEnabled(Database database) =>
      _lifecycle.verifyForeignKeysEnabled(database);

  Future<void> configureDatabasePragmas(
    Database database, {
    bool inTransaction = false,
  }) =>
      _lifecycle.configureDatabasePragmas(
        database,
        inTransaction: inTransaction,
      );
}
