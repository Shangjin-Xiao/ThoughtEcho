/// Basic unit tests for DatabaseService
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:uuid/uuid.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseService Tests', () {
    late DatabaseService databaseService;

    setUp(() {
      databaseService = DatabaseService();
    });

    test('should create DatabaseService instance', () {
      expect(databaseService, isNotNull);
    });

    test('should create Quote model correctly', () {
      final quote = Quote(
        content: '测试内容',
        date: DateTime.now().toIso8601String(),
      );

      expect(quote.content, equals('测试内容'));
      expect(quote.date, isNotEmpty);
    });

    test('should create NoteTag model correctly', () {
      final category = NoteTag(id: 'test-id', name: '测试分类');

      expect(category.id, equals('test-id'));
      expect(category.name, equals('测试分类'));
    });

    group('getQuotes query regression tests', () {
      late Database db;

      setUp(() async {
        await TestHarness.initialize();
        DatabaseService.clearTestDatabase();
        databaseService = DatabaseService();

        db = await databaseFactory.openDatabase(inMemoryDatabasePath);
        await DatabaseSchemaDefinitions().createCurrentSchema(db);

        DatabaseService.setTestDatabase(db);
        await databaseService.init();
      });

      tearDown(() async {
        DatabaseService.clearTestDatabase();
        await db.close();
      });

      test(
          'getUserQuotes logs warning and completes without throwing when batch.commit() returns non-List element',
          () async {
        final now = DateTime.now().toUtc();
        final id = const Uuid().v4();
        final quote = Quote(
          id: id,
          content: 'Test quote for getUserQuotes corrupted batch commit',
          date: now.toIso8601String(),
        );

        await databaseService.addQuote(quote);
        await db.insert('quote_tags', {'quote_id': id, 'tag_id': 'tag_1'});

        final wrappedDb = _CorruptedBatchDatabase(
          db,
          batchResults: ['invalid_batch_element', 99],
        );
        DatabaseService.setTestDatabase(wrappedDb);

        UnifiedLogService.instance.clearMemoryLogs();
        final quotes = await databaseService.getUserQuotes();

        expect(quotes.length, equals(1));
        expect(quotes.first.id, equals(id));
        expect(quotes.first.tagIds, isEmpty);

        final warningLogs = UnifiedLogService.instance.logs
            .where((l) => l.message.contains('批量关联查询标签返回非 List 结果'))
            .toList();
        expect(warningLogs, isNotEmpty);
        expect(warningLogs.first.level, equals(UnifiedLogLevel.warning));

        DatabaseService.setTestDatabase(db);
      });

      test(
          'getAllQuotes completes without throwing when batch.commit() returns non-List element',
          () async {
        final now = DateTime.now().toUtc();
        final id = const Uuid().v4();
        final quote = Quote(
          id: id,
          content: 'Test quote for getAllQuotes corrupted batch commit',
          date: now.toIso8601String(),
        );

        await databaseService.addQuote(quote);
        await db.insert('quote_tags', {'quote_id': id, 'tag_id': 'tag_2'});

        final wrappedDb = _CorruptedBatchDatabase(
          db,
          batchResults: ['invalid_batch_element', 100],
        );
        DatabaseService.setTestDatabase(wrappedDb);

        final quotes = await databaseService.getAllQuotes();

        expect(quotes.length, equals(1));
        expect(quotes.first.id, equals(id));
        expect(quotes.first.tagIds, isEmpty);

        DatabaseService.setTestDatabase(db);
      });
    });
  });
}

class _CorruptedBatchDatabase implements Database {
  final Database _inner;
  final List<dynamic> batchResults;

  _CorruptedBatchDatabase(this._inner, {required this.batchResults});

  @override
  Batch batch() => _CorruptedBatch(_inner.batch(), batchResults);

  @override
  bool get isOpen => _inner.isOpen;

  @override
  String get path => _inner.path;

  @override
  Future<void> close() => _inner.close();

  @override
  Database get database => this;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) =>
      _inner.query(
        table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) =>
      _inner.rawQuery(sql, arguments);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _inner.insert(
        table,
        values,
        nullColumnHack: nullColumnHack,
        conflictAlgorithm: conflictAlgorithm,
      );

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _inner.rawInsert(sql, arguments);

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _inner.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _inner.rawUpdate(sql, arguments);

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) =>
      _inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _inner.rawDelete(sql, arguments);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _inner.execute(sql, arguments);

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) =>
      _inner.transaction(action, exclusive: exclusive);

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      _inner.readTransaction(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CorruptedBatch implements Batch {
  final Batch _inner;
  final List<dynamic> _results;

  _CorruptedBatch(this._inner, this._results);

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) async {
    return _results;
  }

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) =>
      _inner.apply(noResult: noResult, continueOnError: continueOnError);

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  void execute(String sql, [List<Object?>? arguments]) =>
      _inner.execute(sql, arguments);

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _inner.insert(
        table,
        values,
        nullColumnHack: nullColumnHack,
        conflictAlgorithm: conflictAlgorithm,
      );

  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) =>
      _inner.query(
        table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      _inner.rawDelete(sql, arguments);

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) =>
      _inner.rawInsert(sql, arguments);

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      _inner.rawQuery(sql, arguments);

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      _inner.rawUpdate(sql, arguments);

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _inner.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
