import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_backup_service.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late DatabaseBackupService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  setUp(() async {
    final dbPath = join(Directory.systemTemp.path, 'test_backup_merge.db');
    if (File(dbPath).existsSync()) {
      File(dbPath).deleteSync();
    }
    db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await DatabaseSchemaManager().createTables(db);
      },
    );
    service = DatabaseBackupService();
  });

  tearDown(() async {
    await db.close();
  });

  test('LWW Merge should correctly handle categories and quotes', () async {
    // 1. Prepare existing data
    await db.insert('categories', {
      'id': 'cat_1',
      'name': 'Old Category',
      'last_modified': '2023-01-01T00:00:00Z',
    });
    await db.insert('quotes', {
      'id': 'quote_1',
      'content': 'Old Content',
      'date': '2023-01-01T00:00:00Z',
      'last_modified': '2023-01-01T00:00:00Z',
    });

    // 2. Data to merge
    final mergeData = {
      'categories': [
        {
          'id': 'cat_1',
          'name': 'New Category Name', // Name match might happen or ID match
          'last_modified': '2023-02-01T00:00:00Z',
        },
        {
          'id': 'cat_2',
          'name': 'Brand New Category',
          'last_modified': '2023-02-01T00:00:00Z',
        }
      ],
      'quotes': [
        {
          'id': 'quote_1',
          'content': 'New Content',
          'date': '2023-01-01T00:00:00Z',
          'last_modified': '2023-02-01T00:00:00Z',
          'tag_ids': 'cat_1,cat_2',
        },
        {
          'id': 'quote_2',
          'content': 'Another Quote',
          'date': '2023-02-01T00:00:00Z',
          'last_modified': '2023-02-01T00:00:00Z',
        }
      ],
    };

    // 3. Execute merge
    final report = await service.importDataWithLWWMerge(db, mergeData);

    // 4. Verify results
    expect(report.updatedCategories, 1);
    expect(report.insertedCategories, 1);
    expect(report.updatedQuotes, 1);
    expect(report.insertedQuotes, 1);

    final cat1 =
        (await db.query('categories', where: 'id = ?', whereArgs: ['cat_1']))
            .first;
    expect(cat1['name'], 'New Category Name');

    final quote1 =
        (await db.query('quotes', where: 'id = ?', whereArgs: ['quote_1']))
            .first;
    expect(quote1['content'], 'New Content');

    final tags = await db
        .query('quote_tags', where: 'quote_id = ?', whereArgs: ['quote_1']);
    expect(tags.length, 2);
  });

  group('外来数据的值域收敛', () {
    // 起因：一份手写的 demo JSON，`"sentiment": "thoughtful"`。导入侧原来只过滤
    // 不认识的**列**，从不看**值**，于是它原样落库；笔记显示正常，一保存就报
    // 「笔记数据无效」——读（fromJson）不查这个字段，写（validationError）查。

    /// demo JSON 里那条真实数据，只留下和本组用例相关的字段。
    Map<String, dynamic> demoQuote() => {
          'id': 'demo-quote-zh-001',
          'content': '我常以为是丑女造就了美人。',
          'date': '2026-08-22T17:40:00.000Z',
          'last_modified': '2026-08-22T17:40:00.000Z',
          'sentiment': 'thoughtful',
          'color_hex': '#7A5530',
        };

    Future<Quote> readBackFirstQuote() async {
      final rows = await db.query('quotes');
      expect(rows, hasLength(1));
      return Quote.fromJson(Map<String, dynamic>.from(rows.first));
    }

    test('合并导入：越界的 sentiment 被清洗，笔记保持可保存', () async {
      final report = await service.importDataWithLWWMerge(db, {
        'categories': [],
        'quotes': [demoQuote()],
      });

      expect(report.insertedQuotes, 1);
      // 不静默：清洗过几处要能报给用户。
      expect(report.sanitizedFields, 1);

      final quote = await readBackFirstQuote();
      expect(quote.sentiment, isNull);
      expect(quote.content, '我常以为是丑女造就了美人。');
      expect(quote.colorHex, '#7A5530');
      // 这一条就是原来的 bug：能读出来，却存不回去。
      expect(quote.validationError, isNull);
    });

    test('覆盖导入：同样收敛，两条导入路径不能有一条留着洞', () async {
      await service.importDataFromMap(db, {
        'categories': [],
        'quotes': [demoQuote()],
      });

      final quote = await readBackFirstQuote();
      expect(quote.sentiment, isNull);
      expect(quote.validationError, isNull);
    });

    test('认得的 sentiment 原样保留，不计入清洗', () async {
      final report = await service.importDataWithLWWMerge(db, {
        'categories': [],
        'quotes': [
          {...demoQuote(), 'sentiment': 'positive'},
        ],
      });

      expect(report.sanitizedFields, 0);
      expect((await readBackFirstQuote()).sentiment, 'positive');
    });

    test('坏日期被收敛掉：它会让整页笔记加载失败，不只是这一条', () async {
      // date 读的时候就要查，fromJson 直接抛异常，而列表反序列化没有逐行兜底。
      final report = await service.importDataWithLWWMerge(db, {
        'categories': [],
        'quotes': [
          {...demoQuote(), 'sentiment': 'positive', 'date': '不是日期'},
        ],
      });

      expect(report.sanitizedFields, 1);
      final quote = await readBackFirstQuote();
      expect(Quote.isValidDate(quote.date), isTrue);
    });

    test('正文为空的笔记不入库：这种行读出来会炸掉整页', () async {
      final report = await service.importDataWithLWWMerge(db, {
        'categories': [],
        'quotes': [
          {...demoQuote(), 'sentiment': 'positive', 'content': ''},
        ],
      });

      expect(report.insertedQuotes, 0);
      expect(report.skippedQuotes, 1);
      expect(await db.query('quotes'), isEmpty);
    });

    test('正文为空但有 Delta 时从 Delta 捞回正文', () async {
      await service.importDataWithLWWMerge(db, {
        'categories': [],
        'quotes': [
          {
            ...demoQuote(),
            'sentiment': 'positive',
            'content': '',
            'delta_content': '[{"insert":"从 Delta 捞回来的正文\\n"}]',
          },
        ],
      });

      expect((await readBackFirstQuote()).content, contains('捞回来的正文'));
    });

    test('已经中招的库能被一次性修好：删导入代码救不回旧数据', () async {
      // 旧版本导入遗留的行，直接写进库模拟。
      await db.insert('quotes', {
        'id': 'demo-quote-zh-001',
        'content': '我常以为是丑女造就了美人。',
        'date': '2026-08-22T17:40:00.000Z',
        'sentiment': 'thoughtful',
      });
      await db.insert('quotes', {
        'id': 'demo-quote-zh-006',
        'content': '灵感如微光。',
        'date': '2026-08-17T08:20:00.000Z',
        'sentiment': 'positive',
      });
      await db.insert('quotes', {
        'id': 'legacy-label',
        'content': '存的是中文标签而不是 key 的历史数据。',
        'date': '2026-08-17T08:20:00.000Z',
        'sentiment': '积极',
      });

      await DatabaseSchemaManager().repairOutOfDomainSentiment(db);

      Future<String?> sentimentOf(String id) async =>
          (await db.query('quotes', where: 'id = ?', whereArgs: [id]))
              .first['sentiment'] as String?;

      expect(await sentimentOf('demo-quote-zh-001'), isNull); // 认不出来 → 置空
      expect(await sentimentOf('demo-quote-zh-006'), 'positive'); // 合法 → 不动
      expect(await sentimentOf('legacy-label'), 'positive'); // 中文标签 → 收成 key
    });
  });
}
