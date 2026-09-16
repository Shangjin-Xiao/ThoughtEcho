import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/media_reference_service.dart';

/// `getReferenceCountForMediaRelativePath` 是 WebDAV 判断"云端附件是否仍被引用"
/// 的依据：判错为 0 会漏下载照片，判错为正数会把用户已删除的附件重新拉回来。
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

    // 引用行通过外键指向笔记，夹具必须先有父笔记
    await db.insert('quotes', {
      'id': 'q1',
      'content': '正文',
      'date': '2026-08-21T00:00:00.000Z',
    });
  });

  tearDown(() async {
    MediaReferenceService.clearDatabaseForTesting();
    await db.close();
  });

  group('getReferenceCountForMediaRelativePath', () {
    test('命中本机标准相对路径的引用', () async {
      expect(
        await MediaReferenceService.addReference(
          '$iosContainer/media/images/a.jpg',
          'q1',
          cachedAppPath: iosContainer,
        ),
        isTrue,
      );

      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'images/a.jpg',
        ),
        1,
      );
    });

    test('老版本写入的外来绝对路径引用行也能命中，不再漏下载', () async {
      // 老版本 _normalizeFilePath 遇到非本机前缀会原样存下来源设备的绝对路径
      expect(
        await MediaReferenceService.addReference(
          '$androidDocs/media/images/a.jpg',
          'q1',
          cachedAppPath: iosContainer,
        ),
        isTrue,
      );

      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'images/a.jpg',
        ),
        1,
      );
    });

    test('无人引用的云端附件计为 0，不会让已删除的照片复活', () async {
      expect(
        await MediaReferenceService.addReference(
          '$iosContainer/media/images/other.jpg',
          'q1',
          cachedAppPath: iosContainer,
        ),
        isTrue,
      );

      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'images/a.jpg',
        ),
        0,
      );
      // 同名不同目录不算引用
      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'videos/other.jpg',
        ),
        0,
      );
    });

    test('尾段匹配区分大小写，不同大小写的文件不算同一个附件', () async {
      // 区分大小写的文件系统上 A.jpg 与 a.jpg 是两个文件；
      // SQLite 的 LIKE 对 ASCII 默认不区分大小写，这里必须用大小写敏感的比较
      expect(
        await MediaReferenceService.addReference(
          '$androidDocs/media/images/A.jpg',
          'q1',
          cachedAppPath: iosContainer,
        ),
        isTrue,
      );

      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'images/a.jpg',
        ),
        0,
      );
      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'images/A.jpg',
        ),
        1,
      );
    });

    test('文件名中的 % 与 _ 按字面匹配，不当作通配符', () async {
      expect(
        await MediaReferenceService.addReference(
          '$androidDocs/media/images/a%_x.jpg',
          'q1',
          cachedAppPath: iosContainer,
        ),
        isTrue,
      );

      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'images/a%_x.jpg',
        ),
        1,
      );
      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'images/aZZx.jpg',
        ),
        0,
      );
    });

    test('无法识别为媒体尾段的路径计为 0', () async {
      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          '../etc/passwd',
        ),
        0,
      );
      expect(
        await MediaReferenceService.getReferenceCountForMediaRelativePath(
          'html/page.html',
        ),
        0,
      );
    });

    test('数据库查询异常时向上抛出而不是静默返回 0', () async {
      await db.close();

      expect(
        () => MediaReferenceService.getReferenceCountForMediaRelativePath(
          'images/a.jpg',
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        () => MediaReferenceService.getReferenceCount(
          '$iosContainer/media/images/a.jpg',
          cachedAppPath: iosContainer,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('syncQuoteMediaReferences 事务原子性保护', () {
    test('成功同步笔记媒体引用', () async {
      final quote = Quote(
        id: 'q1',
        content: '图文笔记',
        deltaContent:
            '[{"insert":{"image":"images/new_img.jpg"}},{"insert":"\\n"}]',
        date: '2026-08-21T00:00:00.000Z',
      );

      final success = await MediaReferenceService.syncQuoteMediaReferences(
        quote,
        cachedAppPath: iosContainer,
      );
      expect(success, isTrue);

      final refs = await MediaReferenceService.getReferencedFiles('q1');
      expect(refs, contains('images/new_img.jpg'));
    });

    test('同步过程中遇到插入异常时回滚且保留原有引用', () async {
      await MediaReferenceService.addReference('images/old_img.jpg', 'q1');

      // 创建触发器使得向 media_references 的插入操作失败，模拟事务中途崩溃
      await db.execute('''
        CREATE TRIGGER fail_media_ref_insert
        BEFORE INSERT ON media_references
        BEGIN
          SELECT RAISE(ABORT, 'forced insert failure');
        END;
      ''');

      final quote = Quote(
        id: 'q1',
        content: '尝试同步',
        deltaContent:
            '[{"insert":{"image":"images/new_img.jpg"}},{"insert":"\\n"}]',
        date: '2026-08-21T00:00:00.000Z',
      );

      final success = await MediaReferenceService.syncQuoteMediaReferences(
        quote,
        cachedAppPath: iosContainer,
      );
      expect(success, isFalse);

      // 清除触发器，检查数据库中的引用
      await db.execute('DROP TRIGGER fail_media_ref_insert');

      // 验证事务发生回滚，旧引用未被删除
      final refs = await MediaReferenceService.getReferencedFiles('q1');
      expect(refs, contains('images/old_img.jpg'));
      expect(refs, isNot(contains('images/new_img.jpg')));
    });

    test('syncQuoteMediaReferencesWithTransaction 在发生异常时重新抛出以触发外层事务回滚',
        () async {
      await MediaReferenceService.addReference('images/old_img.jpg', 'q1');

      await db.execute('''
        CREATE TRIGGER fail_media_ref_insert_txn
        BEFORE INSERT ON media_references
        BEGIN
          SELECT RAISE(ABORT, 'forced insert failure');
        END;
      ''');

      final quote = Quote(
        id: 'q1',
        content: '测试重新抛出',
        deltaContent:
            '[{"insert":{"image":"images/new_img.jpg"}},{"insert":"\\n"}]',
        date: '2026-08-21T00:00:00.000Z',
      );

      await expectLater(
        () => db.transaction((txn) async {
          await MediaReferenceService.syncQuoteMediaReferencesWithTransaction(
            txn,
            quote,
            cachedAppPath: iosContainer,
          );
        }),
        throwsA(isA<DatabaseException>()),
      );

      await db.execute('DROP TRIGGER fail_media_ref_insert_txn');

      // 验证外层事务回滚，旧引用保持完好
      final refs = await MediaReferenceService.getReferencedFiles('q1');
      expect(refs, contains('images/old_img.jpg'));
      expect(refs, isNot(contains('images/new_img.jpg')));
    });
  });
}
