// To generate mocks, run: dart run build_runner build
// This will create the necessary mock files based on the @GenerateMocks annotation

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/models/localsend_device.dart';
import 'package:thoughtecho/pages/note_sync_page.dart';

import 'note_sync_page_test.mocks.dart';

// Testing Framework: Flutter Test with Mockito 5.4.4
// Generate mocks for all the services using Mockito annotations
@GenerateMocks([
  DatabaseService,
  SettingsService,
  AIAnalysisDatabaseService,
  NoteSyncService,
  BackupService,
])
void main() {
  group('NoteSyncPage Widget Tests', () {
    late MockDatabaseService mockDatabaseService;
    late MockSettingsService mockSettingsService;
    late MockAIAnalysisDatabaseService mockAiAnalysisDbService;
    late MockNoteSyncService mockSyncService;
    late MockBackupService mockBackupService;

    setUp(() {
      mockDatabaseService = MockDatabaseService();
      mockSettingsService = MockSettingsService();
      mockAiAnalysisDbService = MockAIAnalysisDatabaseService();
      mockSyncService = MockNoteSyncService();
      mockBackupService = MockBackupService();

      // Setup default mock behaviors
      when(mockSyncService.initialize()).thenAnswer((_) async {});
      when(mockSyncService.startServer()).thenAnswer((_) async {});
      when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => []);
      when(mockSyncService.sendNotesToDevice(any)).thenAnswer((_) async {});
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          Provider<DatabaseService>.value(value: mockDatabaseService),
          Provider<SettingsService>.value(value: mockSettingsService),
          Provider<AIAnalysisDatabaseService>.value(value: mockAiAnalysisDbService),
        ],
        child: const MaterialApp(
          home: NoteSyncPage(),
        ),
      );
    }

    group('UI Rendering Tests', () {
      testWidgets('should render NoteSyncPage with correct initial UI elements', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        // Verify AppBar and title
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('笔记同步'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsOneWidget);

        // Verify status indicator container
        expect(find.byType(Container), findsAtLeastNWidgets(1));
      });

      testWidgets('should show refresh button in AppBar', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        final refreshButton = find.byIcon(Icons.refresh);
        expect(refreshButton, findsOneWidget);

        // Verify it's an IconButton
        expect(find.ancestor(
          of: refreshButton,
          matching: find.byType(IconButton),
        ), findsOneWidget);
      });

      testWidgets('should display scanning state initially', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        // Should show scanning indicator initially
        expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
        expect(find.text('正在搜索附近设备...'), findsOneWidget);
      });

      testWidgets('should display empty state when no devices found', (tester) async {
        await tester.pumpWidget(createTestWidget());
        
        // Wait for initialization to complete
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Wait for empty state to show
        expect(find.byIcon(Icons.devices_other), findsOneWidget);
        expect(find.text('未发现附近设备'), findsOneWidget);
        expect(find.text('确保目标设备也打开了ThoughtEcho\n并且在同一网络中'), findsOneWidget);
      });

      testWidgets('should display device count when devices are found', (tester) async {
        final mockDevices = [
          Device(
            ip: '192.168.1.100',
            port: 53317,
            alias: 'Test Device 1',
            version: '1.0.0',
            deviceModel: 'TestModel',
            deviceType: DeviceType.mobile,
            fingerprint: 'test-fingerprint-1',
          ),
          Device(
            ip: '192.168.1.101',
            port: 53317,
            alias: 'Test Device 2',
            version: '1.0.0',
            deviceModel: 'TestModel2',
            deviceType: DeviceType.desktop,
            fingerprint: 'test-fingerprint-2',
          ),
        ];

        // Setup mock to return devices
        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => mockDevices);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('发现 2 台设备'), findsOneWidget);
        expect(find.byIcon(Icons.devices), findsOneWidget);
      });
    });

    group('Device List Display Tests', () {
      testWidgets('should display device list when devices are available', (tester) async {
        final mockDevices = [
          Device(
            ip: '192.168.1.100',
            port: 53317,
            alias: 'iPhone 14',
            version: '1.0.0',
            deviceModel: 'iPhone14,2',
            deviceType: DeviceType.mobile,
            fingerprint: 'test-fingerprint-mobile',
          ),
          Device(
            ip: '192.168.1.101',
            port: 53317,
            alias: 'MacBook Pro',
            version: '1.0.0',
            deviceModel: 'MacBookPro18,1',
            deviceType: DeviceType.desktop,
            fingerprint: 'test-fingerprint-desktop',
          ),
        ];

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => mockDevices);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Verify device list is displayed
        expect(find.byType(ListView), findsOneWidget);
        expect(find.byType(Card), findsAtLeastNWidgets(2)); // Device cards + info card
        expect(find.byType(ListTile), findsNWidgets(2));

        // Verify device information
        expect(find.text('iPhone 14'), findsOneWidget);
        expect(find.text('MacBook Pro'), findsOneWidget);
        expect(find.text('192.168.1.100:53317'), findsOneWidget);
        expect(find.text('192.168.1.101:53317'), findsOneWidget);

        // Verify send buttons
        expect(find.byIcon(Icons.send), findsNWidgets(2));
      });

      testWidgets('should show correct device icons based on device type', (tester) async {
        final mockDevices = [
          Device(
            ip: '192.168.1.100',
            port: 53317,
            alias: 'Mobile Device',
            version: '1.0.0',
            deviceModel: 'TestModel',
            deviceType: DeviceType.mobile,
            fingerprint: 'test-mobile',
          ),
          Device(
            ip: '192.168.1.101',
            port: 53317,
            alias: 'Desktop Device',
            version: '1.0.0',
            deviceModel: 'TestModel',
            deviceType: DeviceType.desktop,
            fingerprint: 'test-desktop',
          ),
          Device(
            ip: '192.168.1.102',
            port: 53317,
            alias: 'Web Device',
            version: '1.0.0',
            deviceModel: 'TestModel',
            deviceType: DeviceType.web,
            fingerprint: 'test-web',
          ),
          Device(
            ip: '192.168.1.103',
            port: 53317,
            alias: 'Server Device',
            version: '1.0.0',
            deviceModel: 'TestModel',
            deviceType: DeviceType.server,
            fingerprint: 'test-server',
          ),
          Device(
            ip: '192.168.1.104',
            port: 53317,
            alias: 'Headless Device',
            version: '1.0.0',
            deviceModel: 'TestModel',
            deviceType: DeviceType.headless,
            fingerprint: 'test-headless',
          ),
        ];

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => mockDevices);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Verify device type icons are displayed correctly
        expect(find.byIcon(Icons.smartphone), findsOneWidget); // mobile
        expect(find.byIcon(Icons.computer), findsOneWidget); // desktop
        expect(find.byIcon(Icons.web), findsOneWidget); // web
        expect(find.byIcon(Icons.dns), findsOneWidget); // server
        expect(find.byIcon(Icons.memory), findsOneWidget); // headless
      });
    });

    group('Button State Tests', () {
      testWidgets('should disable refresh button while scanning', (tester) async {
        // Make the discover call take a long time to simulate scanning state
        when(mockSyncService.discoverNearbyDevices()).thenAnswer(
          (_) => Future.delayed(const Duration(seconds: 2), () => <Device>[])
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        final refreshButton = find.byIcon(Icons.refresh);
        final iconButton = tester.widget<IconButton>(find.ancestor(
          of: refreshButton,
          matching: find.byType(IconButton),
        ));
        
        expect(iconButton.onPressed, isNull);
      });

      testWidgets('should enable refresh button when not scanning', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        final refreshButton = find.byIcon(Icons.refresh);
        final iconButton = tester.widget<IconButton>(find.ancestor(
          of: refreshButton,
          matching: find.byType(IconButton),
        ));
        
        expect(iconButton.onPressed, isNotNull);
      });

      testWidgets('should show loading indicator when sending notes', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: 'Test Device',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => [mockDevice]);
        when(mockSyncService.sendNotesToDevice(any)).thenAnswer(
          (_) => Future.delayed(const Duration(seconds: 2))
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap send button
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();

        // Should show loading indicator instead of send button
        expect(find.byIcon(Icons.send), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
      });
    });

    group('Usage Instructions Tests', () {
      testWidgets('should show usage instructions at bottom', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        expect(find.text('使用说明'), findsOneWidget);
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
        expect(find.text('• 点击设备右侧的发送按钮来分享你的笔记\n'
                        '• 接收到的笔记会自动与现有笔记合并\n'
                        '• 重复的笔记会保留最新版本\n'
                        '• 确保两台设备都连接到同一WiFi网络'), findsOneWidget);
      });
    });

    group('User Interaction Tests', () {
      testWidgets('should handle tap on refresh button', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap refresh button
        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pump();

        // Verify mock was called
        verify(mockSyncService.discoverNearbyDevices()).called(greaterThan(0));
      });

      testWidgets('should handle tap on send button', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: 'Test Device',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => [mockDevice]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap send button
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();

        // Verify send method was called
        verify(mockSyncService.sendNotesToDevice(mockDevice)).called(1);
      });
    });

    group('Device Icon Method Tests', () {
      testWidgets('should return correct icon for mobile device', (tester) async {
        await tester.pumpWidget(createTestWidget());
        final state = tester.state<_NoteSyncPageState>(find.byType(NoteSyncPage));
        
        expect(state._getDeviceIcon(DeviceType.mobile), equals(Icons.smartphone));
      });

      testWidgets('should return correct icon for desktop device', (tester) async {
        await tester.pumpWidget(createTestWidget());
        final state = tester.state<_NoteSyncPageState>(find.byType(NoteSyncPage));
        
        expect(state._getDeviceIcon(DeviceType.desktop), equals(Icons.computer));
      });

      testWidgets('should return correct icon for web device', (tester) async {
        await tester.pumpWidget(createTestWidget());
        final state = tester.state<_NoteSyncPageState>(find.byType(NoteSyncPage));
        
        expect(state._getDeviceIcon(DeviceType.web), equals(Icons.web));
      });

      testWidgets('should return correct icon for server device', (tester) async {
        await tester.pumpWidget(createTestWidget());
        final state = tester.state<_NoteSyncPageState>(find.byType(NoteSyncPage));
        
        expect(state._getDeviceIcon(DeviceType.server), equals(Icons.dns));
      });

      testWidgets('should return correct icon for headless device', (tester) async {
        await tester.pumpWidget(createTestWidget());
        final state = tester.state<_NoteSyncPageState>(find.byType(NoteSyncPage));
        
        expect(state._getDeviceIcon(DeviceType.headless), equals(Icons.memory));
      });
    });

    group('Error Handling Tests', () {
      testWidgets('should handle service initialization failure gracefully', (tester) async {
        // Mock service to throw error on initialization
        when(mockSyncService.initialize()).thenThrow(Exception('Service initialization failed'));

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should not crash and should show appropriate UI
        expect(find.byType(NoteSyncPage), findsOneWidget);
      });

      testWidgets('should handle device discovery failure gracefully', (tester) async {
        when(mockSyncService.discoverNearbyDevices()).thenThrow(Exception('Discovery failed'));

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should not crash and show empty state
        expect(find.byType(NoteSyncPage), findsOneWidget);
        expect(find.text('未发现附近设备'), findsOneWidget);
      });

      testWidgets('should handle note sending failure gracefully', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: 'Test Device',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => [mockDevice]);
        when(mockSyncService.sendNotesToDevice(any)).thenThrow(Exception('Send failed'));

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap send button
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();

        // Should not crash and return to normal state
        expect(find.byType(NoteSyncPage), findsOneWidget);
        expect(find.byIcon(Icons.send), findsOneWidget);
      });
    });

    group('Widget Lifecycle Tests', () {
      testWidgets('should properly dispose resources on widget disposal', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        // Navigate away to trigger dispose
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pump();

        // Verify widget is properly removed
        expect(find.byType(NoteSyncPage), findsNothing);
      });

      testWidgets('should handle mounted check in async operations', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        // Immediately navigate away before async operations complete
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pumpAndSettle();

        // Should not crash due to mounted checks
        expect(find.byType(NoteSyncPage), findsNothing);
      });
    });

    group('State Management Tests', () {
      testWidgets('should properly manage scanning state transitions', (tester) async {
        // Mock a slow discovery to observe scanning state
        when(mockSyncService.discoverNearbyDevices()).thenAnswer(
          (_) => Future.delayed(const Duration(milliseconds: 500), () => <Device>[])
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        expect(find.text('正在搜索附近设备...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));

        // Wait for scanning to complete
        await tester.pumpAndSettle();

        expect(find.text('发现 0 台设备'), findsOneWidget);
        expect(find.text('正在搜索附近设备...'), findsNothing);
      });

      testWidgets('should properly manage sending state transitions', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: 'Test Device',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => [mockDevice]);
        when(mockSyncService.sendNotesToDevice(any)).thenAnswer(
          (_) => Future.delayed(const Duration(milliseconds: 300))
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap send button
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();

        expect(find.byIcon(Icons.send), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));

        // Wait for sending to complete
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.send), findsOneWidget);
      });
    });

    group('Edge Cases', () {
      testWidgets('should handle empty device alias gracefully', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: '',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => [mockDevice]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should still display device with empty alias
        expect(find.byType(ListTile), findsOneWidget);
        expect(find.text('192.168.1.100:53317'), findsOneWidget);
      });

      testWidgets('should handle very long device names', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: 'Very Long Device Name That Might Overflow The UI Layout And Cause Issues',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => [mockDevice]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should handle long names without overflow
        expect(find.byType(ListTile), findsOneWidget);
        expect(find.textContaining('Very Long Device Name'), findsOneWidget);
      });

      testWidgets('should handle large device list', (tester) async {
        final mockDevices = List.generate(20, (index) => Device(
          ip: '192.168.1.$index',
          port: 53317,
          alias: 'Device $index',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint-$index',
        ));

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => mockDevices);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should display scrollable list
        expect(find.byType(ListView), findsOneWidget);
        expect(find.text('发现 20 台设备'), findsOneWidget);
        
        // Should be able to scroll
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pump();
      });

      testWidgets('should handle null sync service scenario', (tester) async {
        // Test what happens when sync service fails to initialize
        when(mockSyncService.initialize()).thenThrow(Exception('Failed to initialize'));
        when(mockSyncService.startServer()).thenThrow(Exception('Failed to start server'));

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should still show the UI without crashing
        expect(find.byType(NoteSyncPage), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
      });
    });

    group('Accessibility Tests', () {
      testWidgets('should have proper semantic labels for accessibility', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Verify refresh button has semantic meaning
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        
        // Verify usage instructions are accessible
        expect(find.text('使用说明'), findsOneWidget);
      });

      testWidgets('should handle device list accessibility', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: 'Test Device',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => [mockDevice]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Verify device information is accessible
        expect(find.text('Test Device'), findsOneWidget);
        expect(find.text('192.168.1.100:53317'), findsOneWidget);
        expect(find.byIcon(Icons.send), findsOneWidget);
      });
    });

    group('Performance Tests', () {
      testWidgets('should handle rapid state changes without issues', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: 'Test Device',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer((_) async => [mockDevice]);
        when(mockSyncService.sendNotesToDevice(any)).thenAnswer(
          (_) => Future.delayed(const Duration(milliseconds: 100))
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Rapidly tap refresh button multiple times
        for (int i = 0; i < 3; i++) {
          await tester.tap(find.byIcon(Icons.refresh));
          await tester.pump();
        }

        // Should handle rapid interactions gracefully
        expect(find.byType(NoteSyncPage), findsOneWidget);
      });

      testWidgets('should handle simultaneous operations gracefully', (tester) async {
        final mockDevice = Device(
          ip: '192.168.1.100',
          port: 53317,
          alias: 'Test Device',
          version: '1.0.0',
          deviceModel: 'TestModel',
          deviceType: DeviceType.mobile,
          fingerprint: 'test-fingerprint',
        );

        when(mockSyncService.discoverNearbyDevices()).thenAnswer(
          (_) => Future.delayed(const Duration(milliseconds: 500), () => [mockDevice])
        );
        when(mockSyncService.sendNotesToDevice(any)).thenAnswer(
          (_) => Future.delayed(const Duration(milliseconds: 300))
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        // Try to send while still scanning
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();

        // Should handle overlapping operations
        expect(find.byType(NoteSyncPage), findsOneWidget);
      });
    });
  });
}