import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/media_path_repair_service.dart';
import 'package:thoughtecho/services/media_reference_service.dart';

/// 覆盖跨设备同步后媒体照片"同步完成却看不到图"的回归路径：
/// 合并进来的笔记带着来源设备的绝对路径，本机既渲染不出图片，
/// WebDAV 也会因为引用计数为 0 而永远不下载云端附件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const iosContainer =
      '/var/mobile/Containers/Data/Application/BBBB-2222/Documents';
  const androidDocs = '/data/user/0/com.shangjin.thoughtecho/app_flutter';

  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE quotes(
        id TEXT PRIMARY KEY,
        content TEXT,
        delta_content TEXT,
        date TEXT
      )
    ''');
    await MediaReferenceService.initializeTable(db);
    MediaReferenceService.setDatabaseForTesting(db);
  });

  tearDown(() async {
    MediaReferenceService.clearDatabaseForTesting();
    await db.close();
  });

  Future<void> insertQuote(String id, dynamic delta) async {
    await db.insert('quotes', {
      'id': id,
      'content': '正文',
      'delta_content': delta == null ? null : json.encode(delta),
      'date': '2026-08-21T00:00:00.000Z',
    });
  }

  Future<String?> deltaOf(String id) async {
    final rows = await db.query(
      'quotes',
      columns: ['delta_content'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.first['delta_content'] as String?;
  }

  test('把安卓设备同步过来的媒体绝对路径重定基到本机文档目录', () async {
    await insertQuote('q1', [
      {
        'insert': {'image': '$androidDocs/media/images/a.jpg'},
      },
      {'insert': '来自安卓的笔记\n'},
    ]);

    final report = await MediaPathRepairService.repairAllQuotes(
      database: db,
      appPath: iosContainer,
    );

    expect(report.repaired, 1);
    expect(report.hasErrors, isFalse);
    expect(
      await deltaOf('q1'),
      contains('$iosContainer/media/images/a.jpg'),
    );
  });

  test('重复执行不会二次改写，也不会误伤本机路径与纯文本笔记', () async {
    await insertQuote('q1', [
      {
        'insert': {'image': '$iosContainer/media/images/a.jpg'},
      },
    ]);
    await insertQuote('q2', [
      {'insert': '纯文本，没有媒体\n'},
    ]);

    final report = await MediaPathRepairService.repairAllQuotes(
      database: db,
      appPath: iosContainer,
    );

    expect(report.repaired, 0);
    expect(await deltaOf('q1'), contains('$iosContainer/media/images/a.jpg'));
    expect(await deltaOf('q2'), contains('纯文本，没有媒体'));
  });

  test('单条笔记 Delta 损坏时继续修复其它笔记，并把错误记入报告', () async {
    await db.insert('quotes', {
      'id': 'broken',
      'content': '正文',
      'delta_content': '{不是合法的 media JSON',
      'date': '2026-08-21T00:00:00.000Z',
    });
    await insertQuote('ok', [
      {
        'insert': {'image': '$androidDocs/media/images/b.jpg'},
      },
    ]);

    final report = await MediaPathRepairService.repairAllQuotes(
      database: db,
      appPath: iosContainer,
    );

    expect(report.repaired, 1);
    expect(report.hasErrors, isTrue);
    expect(await deltaOf('ok'), contains('$iosContainer/media/images/b.jpg'));
  });

  test('媒体引用重建失败时整页回滚，并让报告带上错误以阻止水位线推进', () async {
    await insertQuote('q1', [
      {
        'insert': {'image': '$androidDocs/media/images/a.jpg'},
      },
    ]);

    // 丢掉引用表，模拟引用重建失败（syncQuoteMediaReferences… 内部吞异常返回 false）
    await db.execute('DROP TABLE media_references');

    final report = await MediaPathRepairService.repairAllQuotes(
      database: db,
      appPath: iosContainer,
    );

    expect(report.repaired, 0);
    expect(report.hasErrors, isTrue);
    // Delta 必须一并回滚：否则下次重试会认为"无需改写"，引用永远补不回来
    expect(await deltaOf('q1'), contains('$androidDocs/media/images/a.jpg'));
  });

  // 修复链路的端到端断言：路径重定基后，WebDAV 的"云端附件是否被引用"判断
  // 必须能命中。`getReferenceCountForMediaRelativePath` 自身的匹配语义
  // 由 media_reference_service_test.dart 覆盖。
  test('修复并重建引用后，云端附件能被判定为"仍被引用"', () async {
    await insertQuote('q1', [
      {
        'insert': {'image': '$androidDocs/media/images/a.jpg'},
      },
    ]);

    await MediaPathRepairService.repairAllQuotes(
      database: db,
      appPath: iosContainer,
    );

    expect(
      await MediaReferenceService.getReferenceCountForMediaRelativePath(
        'images/a.jpg',
      ),
      1,
    );
  });
}
