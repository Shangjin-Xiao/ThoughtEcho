import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/storage_management_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

import '../../test_setup.dart';

class _FakeDatabaseService extends ChangeNotifier implements DatabaseService {
  _FakeDatabaseService({required this.deletedCount});

  final int deletedCount;

  @override
  Future<int> getDeletedQuotesCount() async => deletedCount;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('DatabaseService.${invocation.memberName} 未实现');
}

Widget _buildTestApp({required DatabaseService databaseService}) {
  return ChangeNotifierProvider<DatabaseService>.value(
    value: databaseService,
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: const StorageManagementPage(),
    ),
  );
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 600));
}

var _logServiceDisposed = false;

void _disposeLogServiceOnce() {
  if (_logServiceDisposed) return;
  UnifiedLogService.instance.dispose();
  _logServiceDisposed = true;
}

Future<void> _pumpUntilStorageContentLoaded(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    if (find.text('总占用空间').evaluate().isNotEmpty) {
      return;
    }
  }
  fail('存储管理页面内容未在预期时间内加载完成');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupTestEnvironment();
  });

  group('StorageManagementPage', () {
    testWidgets('回收站有内容时显示低密度占用提示', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          databaseService: _FakeDatabaseService(deletedCount: 3),
        ),
      );

      await _pumpUntilStorageContentLoaded(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(find.text('回收站中有 3 条笔记，仍会占用数据库和附件空间。'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '查看回收站'), findsOneWidget);

      await _disposeApp(tester);
      _disposeLogServiceOnce();
    });

    testWidgets('回收站为空时不显示占用提示', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          databaseService: _FakeDatabaseService(deletedCount: 0),
        ),
      );

      await _pumpUntilStorageContentLoaded(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(find.textContaining('回收站中有'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '查看回收站'), findsNothing);

      await _disposeApp(tester);
      _disposeLogServiceOnce();
    });
  });
}
