import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/pages/note_sync_page.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';

// 生成Mock类
@GenerateMocks([NoteSyncService])
import 'note_sync_page_test.mocks.dart';

void main() {
  group('NoteSyncPage UI测试', () {
    late MockNoteSyncService mockSyncService;

    setUp(() {
      mockSyncService = MockNoteSyncService();

      // 设置默认返回值
      when(mockSyncService.syncStatus).thenReturn(SyncStatus.idle);
      when(mockSyncService.syncStatusMessage).thenReturn('');
      when(mockSyncService.syncProgress).thenReturn(0.0);
      when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => []);
      when(mockSyncService.startServer()).thenAnswer((_) async {});
      when(mockSyncService.stopServer()).thenAnswer((_) async {});
    });

    Widget createTestWidget() {
      return MaterialApp(
        home: ChangeNotifierProvider<NoteSyncService>.value(
          value: mockSyncService,
          child: const NoteSyncPage(),
        ),
      );
    }

    testWidgets('页面初始状态显示', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 验证页面标题
      expect(find.text('笔记同步'), findsOneWidget);

      // 验证刷新按钮
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // 验证设备发现状态
      expect(find.text('发现 0 台设备'), findsOneWidget);

      // 验证空设备列表提示
      expect(find.text('未发现附近设备'), findsOneWidget);
      expect(find.text('确保目标设备也打开了ThoughtEcho\n并且在同一网络中'), findsOneWidget);
    });

    testWidgets('设备发现状态显示', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 点击刷新按钮开始扫描
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      // 验证扫描状态显示
      expect(find.text('正在搜索附近设备...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('设备列表显示', (WidgetTester tester) async {
      // 模拟发现设备
      final testDevices = [
        Device(
          signalingId: null,
          ip: '192.168.1.100',
          version: '2.1',
          port: 53317,
          https: false,
          fingerprint: 'device1',
          alias: 'Test Device 1',
          deviceModel: 'Test Model',
          deviceType: DeviceType.mobile,
          download: true,
          discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
        ),
        Device(
          signalingId: null,
          ip: '192.168.1.101',
          version: '2.1',
          port: 53317,
          https: false,
          fingerprint: 'device2',
          alias: 'Test Device 2',
          deviceModel: 'Test Model',
          deviceType: DeviceType.desktop,
          download: true,
          discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
        ),
      ];

      when(
        mockSyncService.discoverNearbyDevices(),
      ).thenAnswer((_) async => testDevices);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 模拟设备发现完成
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      // 验证设备数量显示
      expect(find.text('发现 2 台设备'), findsOneWidget);

      // 验证设备列表项
      expect(find.text('Test Device 1'), findsOneWidget);
      expect(find.text('Test Device 2'), findsOneWidget);
      expect(find.text('192.168.1.100:53317'), findsOneWidget);
      expect(find.text('192.168.1.101:53317'), findsOneWidget);

      // 验证设备图标
      expect(find.byIcon(Icons.smartphone), findsOneWidget); // mobile
      expect(find.byIcon(Icons.computer), findsOneWidget); // desktop

      // 验证发送按钮
      expect(find.byIcon(Icons.send), findsNWidgets(2));
    });

    testWidgets('同步状态显示测试', (WidgetTester tester) async {
      // 模拟同步进行中状态
      when(mockSyncService.syncStatus).thenReturn(SyncStatus.packaging);
      when(mockSyncService.syncStatusMessage).thenReturn('正在打包数据...');
      when(mockSyncService.syncProgress).thenReturn(0.3);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 验证同步状态显示
      expect(find.text('正在打包数据...'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);

      // 验证进度指示器
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('同步完成状态显示', (WidgetTester tester) async {
      // 模拟同步完成状态
      when(mockSyncService.syncStatus).thenReturn(SyncStatus.completed);
      when(mockSyncService.syncStatusMessage).thenReturn('同步完成');
      when(mockSyncService.syncProgress).thenReturn(1.0);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 验证完成状态显示
      expect(find.text('同步完成'), findsOneWidget);

      // 完成状态不应该显示进度百分比
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('同步失败状态显示', (WidgetTester tester) async {
      // 模拟同步失败状态
      when(mockSyncService.syncStatus).thenReturn(SyncStatus.failed);
      when(mockSyncService.syncStatusMessage).thenReturn('同步失败: 网络错误');
      when(mockSyncService.syncProgress).thenReturn(0.0);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 验证失败状态显示
      expect(find.text('同步失败: 网络错误'), findsOneWidget);
    });

    testWidgets('发送按钮点击测试', (WidgetTester tester) async {
      final testDevice = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'device1',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      when(
        mockSyncService.discoverNearbyDevices(),
      ).thenAnswer((_) async => [testDevice]);
      when(
        mockSyncService.createSyncPackage(any),
      ).thenAnswer((_) async => 'session-id');

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 模拟设备发现
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      // 点击发送按钮
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // 验证createSyncPackage被调用
      verify(mockSyncService.createSyncPackage(testDevice)).called(1);
    });

    testWidgets('使用说明显示', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 验证使用说明
      expect(find.text('使用说明'), findsOneWidget);
      expect(
        find.text(
          '• 点击设备右侧的发送按钮来分享你的笔记\n'
          '• 接收到的笔记会自动与现有笔记合并\n'
          '• 重复的笔记会保留最新版本\n'
          '• 确保两台设备都连接到同一WiFi网络',
        ),
        findsOneWidget,
      );
    });
  });
}
