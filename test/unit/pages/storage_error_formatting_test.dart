import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/storage_management_page.dart';

class _FakeDatabaseException implements DatabaseException {
  _FakeDatabaseException({
    required this.message,
    this.isReadOnly = false,
  });

  final String message;
  final bool isReadOnly;

  @override
  bool isReadOnlyError() => isReadOnly;

  @override
  bool isDatabaseClosedError() => false;

  @override
  bool isNoSuchTableError([String? table]) => false;

  @override
  bool isSyntaxError() => false;

  @override
  bool isUniqueConstraintError([String? field]) => false;

  @override
  bool isDuplicateColumnError([String? column]) => false;

  @override
  bool isNotNullConstraintError([String? field]) => false;

  @override
  bool isOpenFailedError() => false;

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;

  @override
  String toString() => 'DatabaseException($message)';
}

void main() {
  late AppLocalizations l10nZh;
  late AppLocalizations l10nEn;

  setUpAll(() {
    l10nZh = lookupAppLocalizations(const Locale('zh'));
    l10nEn = lookupAppLocalizations(const Locale('en'));
  });

  group('Storage Management De-Jargonization', () {
    test('app_zh.arb 中存储管理词条已通俗化且无技术黑话', () {
      expect(l10nZh.notesDatabase, '笔记与关联数据');
      expect(l10nZh.aiDatabase, '智能辅助数据');
      expect(l10nZh.logDatabase, '运行与诊断日志');

      expect(l10nZh.notesDatabase, isNot(contains('数据库')));
      expect(l10nZh.aiDatabase, isNot(contains('数据库')));
      expect(l10nZh.logDatabase, isNot(contains('数据库')));

      expect(
        l10nZh.databaseMaintenanceConfirmContent,
        contains('整理数据结构，提升检索性能'),
      );
      expect(
        l10nZh.databaseMaintenanceConfirmContent,
        isNot(contains('释放碎片空间')),
      );
      expect(
        l10nZh.databaseMaintenanceConfirmContent,
        isNot(contains('优化检索索引')),
      );
    });

    test('app_en.arb 中存储管理词条亦已完成重构', () {
      expect(l10nEn.notesDatabase, 'Notes & Associated Data');
      expect(l10nEn.aiDatabase, 'Smart Assistant Data');
      expect(l10nEn.logDatabase, 'Operation & Diagnostic Logs');
      expect(
        l10nEn.databaseMaintenanceConfirmContent,
        contains('Reorganize data structure to improve search performance'),
      );
      expect(
        l10nEn.databaseMaintenanceConfirmContent,
        isNot(contains('Reclaim fragmented storage space')),
      );
    });
  });

  group('formatStorageError Helper', () {
    group('FileSystemException 转换', () {
      test('POSIX 空间不足 (errno 28) 转换为 storageErrorDiskFull', () {
        final err = FileSystemException(
          'write failed',
          '/data/test.db',
          const OSError('No space left on device', 28),
        );
        expect(formatStorageError(err, l10nZh), l10nZh.storageErrorDiskFull);
        expect(
          formatStorageError(err, l10nZh),
          '存储空间不足，请先释放设备空间',
        );
      });

      test('Windows 空间不足 (error 112) 转换为 storageErrorDiskFull', () {
        final err = FileSystemException(
          'WriteFile error',
          'C:\\data\\test.db',
          const OSError('There is not enough space on the disk.', 112),
        );
        expect(formatStorageError(err, l10nZh), l10nZh.storageErrorDiskFull);
      });

      test('无 OSError 但消息包含 disk full 转换为 storageErrorDiskFull', () {
        final err = const FileSystemException('Disk full while writing');
        expect(formatStorageError(err, l10nZh), l10nZh.storageErrorDiskFull);
      });

      test('权限受限 (errno 13 / 5) 转换为 storageErrorPermissionDenied', () {
        final errPosix = FileSystemException(
          'open failed',
          '/data/test.db',
          const OSError('Permission denied', 13),
        );
        expect(
          formatStorageError(errPosix, l10nZh),
          l10nZh.storageErrorPermissionDenied,
        );

        final errWin = FileSystemException(
          'CreateFile error',
          'C:\\data\\test.db',
          const OSError('Access is denied.', 5),
        );
        expect(
          formatStorageError(errWin, l10nZh),
          l10nZh.storageErrorPermissionDenied,
        );
      });

      test('文件未找到 (errno 2) 转换为 storageErrorFileNotFound', () {
        final err = FileSystemException(
          'cannot open',
          '/data/missing.db',
          const OSError('No such file or directory', 2),
        );
        expect(
          formatStorageError(err, l10nZh),
          l10nZh.storageErrorFileNotFound,
        );
      });

      test('常规文件系统异常转换为 storageErrorFileSystem', () {
        final err = FileSystemException(
          'I/O failure',
          '/data/test.db',
          const OSError('Unknown IO', 999),
        );
        expect(
          formatStorageError(err, l10nZh),
          l10nZh.storageErrorFileSystem,
        );
      });
    });

    group('SqliteException 转换', () {
      test('SQLITE_FULL (13) 转换为 storageErrorDiskFull', () {
        final err = SqliteException(
          extendedResultCode: 13,
          message: 'database or disk is full',
        );
        expect(formatStorageError(err, l10nZh), l10nZh.storageErrorDiskFull);
      });

      test('SQLITE_BUSY (5) / SQLITE_LOCKED (6) 转换为 storageErrorDatabaseBusy',
          () {
        final busyErr = SqliteException(
          extendedResultCode: 5,
          message: 'database is locked',
        );
        expect(
          formatStorageError(busyErr, l10nZh),
          l10nZh.storageErrorDatabaseBusy,
        );

        final lockedErr = SqliteException(
          extendedResultCode: 6,
          message: 'table is locked',
        );
        expect(
          formatStorageError(lockedErr, l10nZh),
          l10nZh.storageErrorDatabaseBusy,
        );
      });

      test('SQLITE_READONLY (8) 转换为 storageErrorPermissionDenied', () {
        final readOnlyErr = SqliteException(
          extendedResultCode: 8,
          message: 'attempt to write a readonly database',
        );
        expect(
          formatStorageError(readOnlyErr, l10nZh),
          l10nZh.storageErrorPermissionDenied,
        );
      });

      test('常规 SqliteException 转换为 storageErrorDatabase', () {
        final generalErr = SqliteException(
          extendedResultCode: 1,
          message: 'SQL logic error',
        );
        expect(
          formatStorageError(generalErr, l10nZh),
          l10nZh.storageErrorDatabase,
        );
      });
    });

    group('DatabaseException 转换', () {
      test('只读错误转换为 storageErrorPermissionDenied', () {
        final err = _FakeDatabaseException(
          message: 'attempt to write a readonly database',
          isReadOnly: true,
        );
        expect(
          formatStorageError(err, l10nZh),
          l10nZh.storageErrorPermissionDenied,
        );
      });

      test('空间满错误转换为 storageErrorDiskFull', () {
        final err = _FakeDatabaseException(
          message:
              'SqliteException(13): database or disk is full, full (code 13)',
        );
        expect(
          formatStorageError(err, l10nZh),
          l10nZh.storageErrorDiskFull,
        );
      });

      test('锁错误转换为 storageErrorDatabaseBusy', () {
        final err = _FakeDatabaseException(
          message: 'SqliteException(5): database is locked, busy (code 5)',
        );
        expect(
          formatStorageError(err, l10nZh),
          l10nZh.storageErrorDatabaseBusy,
        );
      });

      test('常规 DatabaseException 转换为 storageErrorDatabase', () {
        final err = _FakeDatabaseException(
          message: 'SqliteException(1): syntax error',
        );
        expect(
          formatStorageError(err, l10nZh),
          l10nZh.storageErrorDatabase,
        );
      });
    });

    group('TimeoutException 及兜底转换', () {
      test('TimeoutException 转换为 storageErrorTimeout', () {
        final err = TimeoutException(
            'Operation timed out', const Duration(seconds: 10));
        expect(formatStorageError(err, l10nZh), l10nZh.storageErrorTimeout);
      });

      test('maintenance_failed 状态码转换为 storageErrorDatabase', () {
        expect(
          formatStorageError('maintenance_failed', l10nZh),
          l10nZh.storageErrorDatabase,
        );
      });

      test('未分类的常规异常兜底为 storageErrorGeneral', () {
        final err = StateError('unexpected state');
        expect(formatStorageError(err, l10nZh), l10nZh.storageErrorGeneral);
      });

      test('任何转换结果均不包含原始类名或调用栈技术字符串', () {
        final errors = <Object>[
          FileSystemException(
            'write failed',
            '/secret/data/thoughtecho.db',
            const OSError('No space left on device', 28),
          ),
          SqliteException(
            extendedResultCode: 13,
            message: 'database or disk is full',
          ),
          _FakeDatabaseException(message: 'SELECT * FROM notes failed'),
          TimeoutException('Database operation timeout'),
          'maintenance_failed',
          Exception('custom unknown error'),
        ];

        for (final err in errors) {
          final formatted = formatStorageError(err, l10nZh);
          expect(formatted, isNot(contains('FileSystemException')));
          expect(formatted, isNot(contains('DatabaseException')));
          expect(formatted, isNot(contains('SqliteException')));
          expect(formatted, isNot(contains('thoughtecho.db')));
          expect(formatted, isNot(contains('SELECT')));
          expect(formatted, isNot(contains('code ')));
        }
      });
    });
  });
}
