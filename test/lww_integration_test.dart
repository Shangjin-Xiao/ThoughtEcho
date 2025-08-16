import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/database_service.dart';
// 移除未使用的 import，保持文件精简

/// 说明:
/// 为 importDataWithLWWMerge 构造四类场景:
/// 1. 新增(remote本地不存在) -> inserted
/// 2. 更新(remote newer) -> updated
/// 3. 跳过(local newer) -> skipped
/// 4. 冲突(时间戳相同但内容不同) -> sameTimestampDiff
///
/// 使用内存/临时数据库 (DatabaseService默认策略会在测试环境创建本地DB)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LWW integration basic scenarios', () {
    late DatabaseService db;

    setUp(() async {
      db = DatabaseService();
      await db.init();
    });

    tearDown(() async {
      // DatabaseService 暂无 close 方法，这里预留资源清理位置
    });

    test('insert/update/skip/conflict counters', () async {
      final now = DateTime.now().toUtc();
      final older = now.subtract(const Duration(minutes: 10)).toIso8601String();
      final newer = now.add(const Duration(minutes: 10)).toIso8601String();
      final same = now.toIso8601String();

      // 预置本地数据: localA(older), localB(newer), localC(same, content X)
      final localQuotes = [
        {
          'id': 'q_local_old',
          'content': 'local old content',
          'date': older,
          'last_modified': older,
        },
        {
          'id': 'q_local_new',
          'content': 'local new content',
          'date': newer,
          'last_modified': newer,
        },
        {
          'id': 'q_conflict',
          'content': 'local conflict content A',
          'date': same,
          'last_modified': same,
        },
      ];

      final initData = {
        'categories': <Map<String, dynamic>>[],
        'quotes': localQuotes,
      };
      await db.importDataFromMap(initData, clearExisting: true);

      // 构造远程数据:
      // - q_insert (新增)
      // - q_local_old (远程 newer -> updated)
      // - q_local_new (本地 newer -> skipped)
      // - q_conflict (same ts diff content -> conflict keep local)
      final remoteData = {
        'categories': <Map<String, dynamic>>[],
        'quotes': [
          {
            'id': 'q_insert',
            'content': 'remote inserted content',
            'date': newer,
            'last_modified': newer,
          },
          {
            'id': 'q_local_old',
            'content': 'remote newer content',
            'date': newer,
            'last_modified': newer,
          },
          {
            'id': 'q_local_new',
            'content': 'remote older content should skip',
            'date': older,
            'last_modified': older,
          },
          {
            'id': 'q_conflict',
            'content': 'remote conflict content B',
            'date': same,
            'last_modified': same,
          },
        ],
      };

      final report = await db.importDataWithLWWMerge(remoteData,
          sourceDevice: 'test-device');

      expect(report.insertedQuotes, 1);
      expect(report.updatedQuotes, 1);
      expect(report.skippedQuotes, 1);
      expect(report.sameTimestampDiffQuotes, 1);
      expect(report.errors.length, 0);

      // 验证数据库最终内容
      final all = await db.getAllQuotes();
      // 转换为 map 方便断言
      final byId = {for (final q in all) q.id!: q};
      expect(byId.containsKey('q_insert'), true);
      expect(byId['q_insert']!.content, 'remote inserted content');
      expect(byId['q_local_old']!.content, 'remote newer content');
      // skipped keeps local
      expect(byId['q_local_new']!.content, 'local new content');
      // conflict keeps local content
      expect(byId['q_conflict']!.content, 'local conflict content A');
    });
  });
}
