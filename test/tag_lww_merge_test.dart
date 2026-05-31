import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('LWW tag merge', () {
    late DatabaseService db;

    setUp(() async {
      db = DatabaseService();
      await db.init();
    });

    tearDown(() {
      db.dispose();
    });

    test('remote tag_ids are mapped and linked without duplication', () async {
      // 准备本地已有分类: name = "工作" (不同ID)
      await db.addCategoryWithId('local-cat-1', '工作');

      final remoteData = {
        'categories': [
          {
            'id': 'remote-cat-a',
            'name': '工作', // 应匹配本地分类并重映射
            'last_modified': DateTime.now().toIso8601String(),
          },
          {
            'id': 'remote-cat-b',
            'name': '生活',
            'last_modified': DateTime.now().toIso8601String(),
          },
        ],
        'quotes': [
          {
            'id': 'quote-1',
            'content': '带有两个标签',
            'date': DateTime.now().toIso8601String(),
            'last_modified': DateTime.now().toIso8601String(),
            'tag_ids': ['remote-cat-a', 'remote-cat-b'],
          },
          {
            'id': 'quote-2',
            'content': '只带一个需要重映射的标签',
            'date': DateTime.now().toIso8601String(),
            'last_modified': DateTime.now().toIso8601String(),
            'tag_ids': 'remote-cat-a',
          },
        ],
      };

      final report = await db.importDataWithLWWMerge(
        remoteData,
        sourceDevice: 'test-device',
      );
      expect(report.errors, isEmpty, reason: '合并不应产生错误: ${report.errors}');

      final categories = await db.getCategories();
      final workCats = categories.where((c) => c.name == '工作').toList();
      expect(workCats.length, 1, reason: '同名分类应被去重');
      final lifeCats = categories.where((c) => c.name == '生活').toList();
      expect(lifeCats.length, 1, reason: '新分类应插入');

      final workLocalId = workCats.first.id;
      final lifeLocalId = lifeCats.first.id;

      // 直接查询 quote_tags 表验证标签关联（exportDataAsMap 已移除）
      final rawDb = DatabaseService.rawDatabaseInstance!;
      final tagRows1 = await rawDb.query(
        'quote_tags',
        where: 'quote_id = ?',
        whereArgs: ['quote-1'],
      );
      final tagRows2 = await rawDb.query(
        'quote_tags',
        where: 'quote_id = ?',
        whereArgs: ['quote-2'],
      );
      final tagIds1 = tagRows1.map((r) => r['tag_id'] as String).toSet();
      final tagIds2 = tagRows2.map((r) => r['tag_id'] as String).toSet();

      expect(tagIds1, {workLocalId, lifeLocalId});
      expect(tagIds2, {workLocalId});
    });

    test('hidden tag is always returned at the end of category list', () async {
      await db.getOrCreateHiddenTag();
      final suffix = DateTime.now().microsecondsSinceEpoch;
      await db.addCategory('隐藏排序测试A_$suffix');
      await db.addCategory('隐藏排序测试B_$suffix');

      final categories = await db.getCategories();

      expect(
        categories.where((c) => c.id == DatabaseService.hiddenTagId).length,
        1,
      );
      expect(categories.last.id, DatabaseService.hiddenTagId);
    });
  });
}
