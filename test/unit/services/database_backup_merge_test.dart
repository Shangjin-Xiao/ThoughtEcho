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

    test('date 不是字符串且缺 last_modified：笔记要进得来，不能被类型错误吞掉', () async {
      // 原来这里是 `quoteData['last_modified'] ??= quoteData['date'] as String?`，
      // date 是数字时那句直接抛类型错误，被外层 catch 吞成「跳过这条笔记」——
      // 收敛逻辑压根没机会跑。
      final quote = demoQuote()
        ..['sentiment'] = 'positive'
        ..['date'] = 20260822
        ..remove('last_modified');

      final report = await service.importDataWithLWWMerge(db, {
        'categories': [],
        'quotes': [quote],
      });

      expect(report.insertedQuotes, 1);
      expect(report.errors, isEmpty);

      final stored = await readBackFirstQuote();
      expect(Quote.isValidDate(stored.date), isTrue);
    });

    test('date 非法且缺 last_modified：不能把非法值抄进 last_modified', () async {
      // last_modified 是 LWW 比较的依据，留一个解析不了的值在库里，之后每一次
      // 合并都会拿它做判断。
      final quote = demoQuote()
        ..['sentiment'] = 'positive'
        ..['date'] = '不是日期'
        ..remove('last_modified');

      await service.importDataWithLWWMerge(db, {
        'categories': [],
        'quotes': [quote],
      });

      final row = (await db.query('quotes')).first;
      expect(Quote.isValidDate(row['date'] as String), isTrue);
      expect(Quote.isValidDate(row['last_modified'] as String), isTrue);
    });

    test('正文为空的笔记不入库：这种行读出来会炸掉整页', () async {
      final report = await service.importDataWithLWWMerge(db, {
        'categories': [],
        'quotes': [
          {...demoQuote(), 'sentiment': 'positive', 'content': ''},
        ],
      });

      expect(report.insertedQuotes, 0);
      // 单独数：这不是 LWW 判定「本地更新」的正常跳过，是数据有问题进不来。
      expect(report.skippedEmptyQuotes, 1);
      expect(report.skippedQuotes, 0);
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

    test('覆盖导入把清洗统计交回调用方，还原页才有东西可展示', () async {
      final stats = await service.importDataFromMap(db, {
        'categories': [],
        'quotes': [
          demoQuote(),
          {...demoQuote(), 'id': 'empty-one', 'content': '', 'sentiment': null},
        ],
      });

      expect(stats.sanitizedFields, 1); // demo-quote-zh-001 的 thoughtful
      expect(stats.skippedEmptyQuotes, 1);
      expect(stats.isClean, isFalse);
    });

    test('一条笔记清洗了三个字段就要报 3，不是 1', () async {
      // sanitizedFields 的口径是**字段数**。按笔记数报会瞒掉同一条笔记里另外两处
      // 被动过的地方，而合并路径用的是 replaced.length，两条路径口径必须一致。
      final stats = await service.importDataFromMap(db, {
        'categories': [],
        'quotes': [
          {
            ...demoQuote(),
            'sentiment': 'thoughtful', // 认不出来 → 归空
            'color_hex': '不是颜色', // 格式不对 → 归空
            'date': '不是日期', // 无法解析 → 回落
          },
        ],
      });

      expect(stats.sanitizedFields, 3);
    });

    test('干净的备份不产生任何清洗统计', () async {
      final stats = await service.importDataFromMap(db, {
        'categories': [],
        'quotes': [
          {...demoQuote(), 'sentiment': 'positive'},
        ],
      });

      expect(stats.isClean, isTrue);
    });

    test('修复是不可逆写入，改列之前必须先把原值快照下来', () async {
      await db.insert('quotes', {
        'id': 'demo-quote-zh-001',
        'content': '我常以为是丑女造就了美人。',
        'date': '2026-08-22T17:40:00.000Z',
        'sentiment': 'thoughtful',
      });

      await DatabaseSchemaManager().repairOutOfDomainSentiment(db);

      // 光把代码回滚是找不回原值的，所以原值要留在 sentiment_backup 里
      // （weather / day_period 那两个同类迁移是同一个规矩）。
      final row = (await db.query('quotes',
              where: 'id = ?', whereArgs: ['demo-quote-zh-001']))
          .first;
      expect(row['sentiment'], isNull);
      expect(row['sentiment_backup'], 'thoughtful');
    });

    test('第二次修复也要留底：快照列已存在不能让新的越界值无处可寻', () async {
      // _ensureBackupColumn 只在建列那一次整列快照，列已存在就直接返回。原值必须
      // 由修复本身那条 UPDATE 写入，否则第二份坏备份导进来就再也找不回原值了。
      await db.insert('quotes', {
        'id': 'first-round',
        'content': '第一批',
        'date': '2026-08-22T17:40:00.000Z',
        'sentiment': 'thoughtful',
      });
      await DatabaseSchemaManager().repairOutOfDomainSentiment(db);

      // 第二轮：快照列此时已经存在。
      await db.insert('quotes', {
        'id': 'second-round',
        'content': '第二批',
        'date': '2026-08-22T17:40:00.000Z',
        'sentiment': 'inspirational',
      });
      await DatabaseSchemaManager().repairOutOfDomainSentiment(db);

      Future<Object?> backupOf(String id) async =>
          (await db.query('quotes', where: 'id = ?', whereArgs: [id]))
              .first['sentiment_backup'];

      expect(await backupOf('first-round'), 'thoughtful');
      expect(await backupOf('second-round'), 'inspirational');
    });
  });
}
