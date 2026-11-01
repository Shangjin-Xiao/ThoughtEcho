import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/pages/note_sync_page.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

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
      when(mockSyncService.awaitingPeerApproval).thenReturn(false);
      when(mockSyncService.awaitingUserApproval).thenReturn(false);
      when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => []);
      when(
        mockSyncService.discoverNearbyDevicesStream(
          timeout: anyNamed('timeout'),
        ),
      ).thenReturn((Stream<List<Device>>.value(const []), () {}));
      when(mockSyncService.startServer()).thenAnswer((_) async {});
      when(mockSyncService.stopServer()).thenAnswer((_) async {});
    });

    Widget createTestWidget() {
      return ChangeNotifierProvider<NoteSyncService>.value(
        value: mockSyncService,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''),
            Locale('zh', ''),
          ],
          home: const NoteSyncPage(),
        ),
      );
    }

    Future<void> pumpUi(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('页面初始状态显示', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      // 验证页面标题
      expect(find.text('笔记同步'), findsOneWidget);

      // 验证刷新按钮
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // 验证设备发现状态
      expect(find.text('发现 0 台设备'), findsOneWidget);

      // 验证空设备列表提示
      expect(find.text('未发现附近设备'), findsOneWidget);
      expect(
        find.text('请确保目标设备也打开了心迹同步页\n并且两台设备在同一WiFi网络中'),
        findsOneWidget,
      );
    });

    testWidgets('设备发现状态显示', (WidgetTester tester) async {
      final discovery = StreamController<List<Device>>();
      addTearDown(discovery.close);
      when(
        mockSyncService.discoverNearbyDevicesStream(
          timeout: anyNamed('timeout'),
        ),
      ).thenReturn((discovery.stream, () {}));
      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      // 验证扫描状态显示
      expect(find.textContaining('搜索中...'), findsOneWidget);
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
        mockSyncService.discoverNearbyDevicesStream(
          timeout: anyNamed('timeout'),
        ),
      ).thenReturn((Stream<List<Device>>.value(testDevices), () {}));

      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      // 验证设备数量显示
      expect(find.text('发现 2 台设备'), findsOneWidget);

      // 验证设备列表项
      expect(find.text('Test Device 1'), findsOneWidget);
      expect(find.text('Test Device 2'), findsOneWidget);
      expect(find.text('局域网在线 · 192.168.1.100'), findsOneWidget);
      expect(find.text('局域网在线 · 192.168.1.101'), findsOneWidget);

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
      await pumpUi(tester);

      // 验证同步状态显示
      expect(find.text('正在打包数据...'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);

      // 验证进度指示器
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('等待对方确认时显示取消发送按钮', (WidgetTester tester) async {
      when(mockSyncService.syncStatus).thenReturn(SyncStatus.packaging);
      when(mockSyncService.syncStatusMessage).thenReturn('等待对方确认同步请求...');
      when(mockSyncService.awaitingPeerApproval).thenReturn(true);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('取消发送'), findsOneWidget);
      await tester.tap(find.text('取消发送'));
      verify(mockSyncService.cancelOngoingSend()).called(1);
    });

    testWidgets('等待对方确认时按返回会取消发送', (tester) async {
      when(mockSyncService.syncStatus).thenReturn(SyncStatus.packaging);
      when(mockSyncService.syncStatusMessage).thenReturn('等待对方确认同步请求...');
      when(mockSyncService.awaitingPeerApproval).thenReturn(true);

      await tester.pumpWidget(createTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('等待对方确认'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));

      verify(mockSyncService.cancelOngoingSend()).called(1);
    });

    testWidgets('同步完成状态显示', (WidgetTester tester) async {
      when(mockSyncService.syncStatus).thenReturn(SyncStatus.packaging);
      when(mockSyncService.syncStatusMessage).thenReturn('正在打包数据...');
      when(mockSyncService.syncProgress).thenReturn(0.5);
      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      when(mockSyncService.syncStatus).thenReturn(SyncStatus.completed);
      when(mockSyncService.syncStatusMessage).thenReturn('同步完成');
      when(mockSyncService.syncProgress).thenReturn(1.0);
      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      expect(find.text('同步完成'), findsWidgets);
    });

    testWidgets('同步失败状态显示', (WidgetTester tester) async {
      when(mockSyncService.syncStatus).thenReturn(SyncStatus.packaging);
      when(mockSyncService.syncStatusMessage).thenReturn('正在打包数据...');
      when(mockSyncService.syncProgress).thenReturn(0.5);
      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      when(mockSyncService.syncStatus).thenReturn(SyncStatus.failed);
      when(mockSyncService.syncStatusMessage).thenReturn('同步失败: 网络错误');
      when(mockSyncService.syncProgress).thenReturn(0.0);
      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      expect(find.text('同步失败: 网络错误'), findsWidgets);
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
        mockSyncService.discoverNearbyDevicesStream(
          timeout: anyNamed('timeout'),
        ),
      ).thenReturn((Stream<List<Device>>.value([testDevice]), () {}));
      when(
        mockSyncService.createSyncPackage(any),
      ).thenAnswer((_) async => 'session-id');

      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      // 点击发送按钮
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.tap(find.text('开始发送'));
      await tester.pump();

      // 验证createSyncPackage被调用
      verify(mockSyncService.createSyncPackage(testDevice)).called(1);
    });

    testWidgets('使用说明显示', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

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

    testWidgets('AutoScrollText 视图使用 RepaintBoundary 隔离绘制图层', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              child: AutoScrollText(
                'Long text content that exceeds viewport width for testing repaint boundary isolation',
              ),
            ),
          ),
        ),
      );

      final autoScrollFinder = find.byType(AutoScrollText);
      expect(autoScrollFinder, findsOneWidget);

      final repaintBoundaryFinder = find.descendant(
        of: autoScrollFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintBoundaryFinder, findsOneWidget);

      final scrollFinder = find.descendant(
        of: repaintBoundaryFinder,
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollFinder, findsOneWidget);

      // 卸载组件并推进时钟，等待未决的延时退出
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('短文本不发生滚动且代际标记正确', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: AutoScrollText('Short text'),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      final state = tester.state<AutoScrollTextState>(
        find.byType(AutoScrollText),
      );
      expect(state.debugAnimationGeneration, 0);

      // 文本没有超出宽度，maxScrollExtent <= 0，不应处于活跃动画中
      await tester.pump(const Duration(seconds: 3));
      expect(state.debugScrollController.hasClients, isTrue);
      expect(
        state.debugScrollController.position.maxScrollExtent,
        lessThanOrEqualTo(0),
      );
      expect(state.debugIsAnimating, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('文本频繁更新时代际递增并重置，无并发动画冲突', (
      WidgetTester tester,
    ) async {
      final longText1 = 'A' * 200;
      final longText2 = 'B' * 200;
      final longText3 = 'C' * 200;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 60,
              child: AutoScrollText(longText1),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final state = tester.state<AutoScrollTextState>(
        find.byType(AutoScrollText),
      );
      expect(state.debugAnimationGeneration, 0);

      // 快速连续更新文本
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 60,
              child: AutoScrollText(longText2),
            ),
          ),
        ),
      );
      expect(state.debugAnimationGeneration, 1);

      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 60,
              child: AutoScrollText(longText3),
            ),
          ),
        ),
      );
      expect(state.debugAnimationGeneration, 2);

      // 推进动画时间，确保不会触发 ScrollController 并发异常或崩溃
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));

      expect(state.debugAnimationGeneration, 2);
      expect(state.debugScrollController.position.pixels, greaterThan(0));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('动画运行过程中卸载组件不抛异常', (WidgetTester tester) async {
      final longText = 'Long text for testing unmount while scrolling ' * 5;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 50,
              child: AutoScrollText(longText),
            ),
          ),
        ),
      );

      await tester.pump();
      // 让动画开始
      await tester.pump(const Duration(seconds: 3));

      // 卸载组件
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(),
          ),
        ),
      );

      // 推进异步时间，旧的动画循环唤醒时应由于 generation 变更与 unmount 立即退出，不抛出异常
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('在 NoteSyncPage 设备卡片中验证 RepaintBoundary 生效', (
      WidgetTester tester,
    ) async {
      final testDevice = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'device1',
        alias:
            'Super Long Device Alias Name That Should Trigger Auto Scroll Text',
        deviceModel: 'Super Long Model Name For Testing Boundary',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      when(
        mockSyncService.discoverNearbyDevicesStream(
          timeout: anyNamed('timeout'),
        ),
      ).thenReturn((Stream<List<Device>>.value([testDevice]), () {}));

      await tester.pumpWidget(createTestWidget());
      await pumpUi(tester);

      // 验证设备卡片中的 AutoScrollText 确实被 RepaintBoundary 包裹
      final autoScrollTexts = find.byType(AutoScrollText);
      expect(autoScrollTexts, findsWidgets);

      for (final element in autoScrollTexts.evaluate()) {
        final descendantRepaint = find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(RepaintBoundary),
        );
        expect(descendantRepaint, findsOneWidget);
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
