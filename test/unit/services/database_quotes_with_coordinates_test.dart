import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';

import '../../test_harness.dart';

/// 地图回忆页的取数：只要有坐标的、没被删也没被隐藏的笔记。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseService.getQuotesWithCoordinates', () {
    late DatabaseService service;
    late Database db;

    setUp(() async {
      await TestHarness.initialize();
      DatabaseService.clearTestDatabase();
      service = DatabaseService();

      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
          CREATE TABLE quotes(
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            date TEXT NOT NULL,
            source TEXT,
            source_author TEXT,
            source_work TEXT,
            ai_analysis TEXT,
            sentiment TEXT,
            keywords TEXT,
            summary TEXT,
            category_id TEXT DEFAULT '',
            color_hex TEXT,
            location TEXT,
            latitude REAL,
            longitude REAL,
            poi_name TEXT,
            weather TEXT,
            temperature TEXT,
            edit_source TEXT,
            delta_content TEXT,
            day_period TEXT,
            last_modified TEXT,
            favorite_count INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            deleted_at TEXT
          )
        ''');
      await db.execute('''
          CREATE TABLE categories(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_default BOOLEAN DEFAULT 0,
            icon_name TEXT,
            last_modified TEXT
          )
        ''');
      await db.execute('''
          CREATE TABLE quote_tags(
            quote_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            PRIMARY KEY (quote_id, tag_id)
          )
        ''');
      await db.execute('''
          CREATE TABLE media_references (
            id TEXT PRIMARY KEY,
            file_path TEXT NOT NULL,
            quote_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(file_path, quote_id)
          )
        ''');
      await db.execute('''
          CREATE TABLE quote_tombstones (
            quote_id TEXT PRIMARY KEY,
            deleted_at TEXT NOT NULL,
            device_id TEXT
          )
        ''');

      DatabaseService.setTestDatabase(db);
      await service.init();
    });

    tearDown(() async {
      DatabaseService.clearTestDatabase();
      await db.close();
    });

    test('只返回带坐标的笔记，没坐标的不上地图', () async {
      await service.addQuote(
        Quote(
          id: 'with-coordinates',
          content: '在芝公园写的',
          date: '2026-08-01T10:00:00.000Z',
          latitude: 35.6547,
          longitude: 139.7490,
          poiName: '芝公园',
        ),
      );
      await service.addQuote(
        Quote(
          id: 'without-coordinates',
          content: '在家里写的',
          date: '2026-08-02T10:00:00.000Z',
        ),
      );

      final points = await service.getQuotesWithCoordinates();

      expect(points.map((p) => p.id), ['with-coordinates']);
      expect(points.single.latitude, closeTo(35.6547, 0.0001));
      expect(points.single.longitude, closeTo(139.7490, 0.0001));
    });

    test('回收站里的笔记不上地图', () async {
      await service.addQuote(
        Quote(
          id: 'kept',
          content: '保留',
          date: '2026-08-01T10:00:00.000Z',
          latitude: 31.2304,
          longitude: 121.4737,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'trashed',
          content: '删掉',
          date: '2026-08-02T10:00:00.000Z',
          latitude: 39.9042,
          longitude: 116.4074,
        ),
      );

      await service.deleteQuote('trashed');

      final points = await service.getQuotesWithCoordinates();

      expect(points.map((p) => p.id), ['kept']);
    });

    test('隐藏笔记不上地图', () async {
      await service.addQuote(
        Quote(
          id: 'visible',
          content: '公开的',
          date: '2026-08-01T10:00:00.000Z',
          latitude: 31.2304,
          longitude: 121.4737,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'hidden',
          content: '隐藏的',
          date: '2026-08-02T10:00:00.000Z',
          latitude: 39.9042,
          longitude: 116.4074,
          tagIds: const [DatabaseService.hiddenTagId],
        ),
      );

      final points = await service.getQuotesWithCoordinates();

      expect(points.map((p) => p.id), ['visible']);
    });

    test('查询失败时抛出，不把故障压成「还没有带位置的笔记」', () async {
      // 地图页靠「空列表」判断该显示引导文案。把失败也压成空，用户看到的
      // 就是一张加载成功的空地图，数据库故障被藏起来了。
      await db.close();

      expect(() => service.getQuotesWithCoordinates(), throwsA(isA<Object>()));
    });

    test('按时间倒序返回', () async {
      await service.addQuote(
        Quote(
          id: 'older',
          content: '早一点',
          date: '2026-08-01T10:00:00.000Z',
          latitude: 31.2304,
          longitude: 121.4737,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'newer',
          content: '晚一点',
          date: '2026-08-05T10:00:00.000Z',
          latitude: 39.9042,
          longitude: 116.4074,
        ),
      );

      final points = await service.getQuotesWithCoordinates();

      expect(points.map((p) => p.id), ['newer', 'older']);
    });

    test('越界坐标不上地图', () async {
      await service.addQuote(
        Quote(
          id: 'out-of-bounds-lat',
          content: '纬度超标',
          date: '2026-08-01T10:00:00.000Z',
          latitude: 91.0,
          longitude: 120.0,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'out-of-bounds-lon',
          content: '经度超标',
          date: '2026-08-02T10:00:00.000Z',
          latitude: 30.0,
          longitude: -185.0,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'valid-bounds',
          content: '合法边界',
          date: '2026-08-03T10:00:00.000Z',
          latitude: -90.0,
          longitude: 180.0,
        ),
      );

      final points = await service.getQuotesWithCoordinates();

      expect(points.map((p) => p.id), ['valid-bounds']);
      expect(points.single.latitude, -90.0);
      expect(points.single.longitude, 180.0);
    });

    test('Bounding Box 视口范围过滤仅返回矩形区域内的坐标点', () async {
      await service.addQuote(
        Quote(
          id: 'beijing',
          content: '北京',
          date: '2026-08-01T10:00:00.000Z',
          latitude: 39.9042,
          longitude: 116.4074,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'shanghai',
          content: '上海',
          date: '2026-08-02T10:00:00.000Z',
          latitude: 31.2304,
          longitude: 121.4737,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'tokyo',
          content: '东京',
          date: '2026-08-03T10:00:00.000Z',
          latitude: 35.6762,
          longitude: 139.6503,
        ),
      );

      // 查询华东/华北区域 bounds [30, 41], [115, 125] -> 北京 + 上海，不含东京
      final points = await service.getQuotesWithCoordinates(
        minLatitude: 30.0,
        maxLatitude: 41.0,
        minLongitude: 115.0,
        maxLongitude: 125.0,
      );

      expect(points.map((p) => p.id), ['shanghai', 'beijing']);
    });

    test('跨越 180 度经线 (Antimeridian) 的 Bounding Box 查询正确包含两侧坐标', () async {
      await service.addQuote(
        Quote(
          id: 'fiji',
          content: '斐济',
          date: '2026-08-01T10:00:00.000Z',
          latitude: -17.7134,
          longitude: 178.0650,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'samoa',
          content: '萨摩亚',
          date: '2026-08-02T10:00:00.000Z',
          latitude: -13.7590,
          longitude: -172.1046,
        ),
      );
      await service.addQuote(
        Quote(
          id: 'london',
          content: '伦敦',
          date: '2026-08-03T10:00:00.000Z',
          latitude: 51.5074,
          longitude: -0.1278,
        ),
      );

      // 视口跨越国际日期变更线: minLon = 170.0, maxLon = -170.0
      final points = await service.getQuotesWithCoordinates(
        minLatitude: -30.0,
        maxLatitude: 0.0,
        minLongitude: 170.0,
        maxLongitude: -170.0,
      );

      expect(points.map((p) => p.id), containsAll(['samoa', 'fiji']));
      expect(points.map((p) => p.id), isNot(contains('london')));
    });

    test('支持 limit 与 offset 分页查询', () async {
      for (int i = 1; i <= 5; i++) {
        await service.addQuote(
          Quote(
            id: 'note-$i',
            content: '笔记 $i',
            date: '2026-08-0${i}T10:00:00.000Z',
            latitude: 30.0 + i,
            longitude: 120.0 + i,
          ),
        );
      }

      // 按时间倒序：note-5, note-4, note-3, note-2, note-1
      final page1 = await service.getQuotesWithCoordinates(limit: 2, offset: 0);
      expect(page1.map((p) => p.id), ['note-5', 'note-4']);

      final page2 = await service.getQuotesWithCoordinates(limit: 2, offset: 2);
      expect(page2.map((p) => p.id), ['note-3', 'note-2']);

      final page3 = await service.getQuotesWithCoordinates(limit: 2, offset: 4);
      expect(page3.map((p) => p.id), ['note-1']);
    });

    test('大量数据 (> 50 条) 触发 Isolate 后台计算解析并保证准确性', () async {
      for (int i = 1; i <= 60; i++) {
        await service.addQuote(
          Quote(
            id: 'bulk-$i',
            content: '大量数据 $i',
            date: '2026-08-01T10:00:00.000Z',
            latitude: 30.0 + (i % 10),
            longitude: 120.0 + (i % 10),
          ),
        );
      }

      final points = await service.getQuotesWithCoordinates();
      expect(points.length, equals(60));
    });
  });
}
