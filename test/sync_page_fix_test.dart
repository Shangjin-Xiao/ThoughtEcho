import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/sync_protocol/constants.dart';

void main() {
  group('同步页面修复验证', () {
    test('ThoughtEchoDiscoveryService 新方法测试', () {
      final discoveryService = ThoughtEchoDiscoveryService();
      
      // 验证新方法存在且不会抛出异常
      expect(() => discoveryService.clearDevices(), returnsNormally);
      
      // 验证设备列表被清空
      expect(discoveryService.devices, isEmpty);
      
      // 清理
      discoveryService.dispose();
    });

    test('设备发现逻辑改进验证', () async {
      // 这个测试主要验证方法签名和基本逻辑
      // 实际的网络功能需要在真实环境中测试
      
      // 验证方法存在且返回正确类型
      expect(ThoughtEchoDiscoveryService().devices, isA<List>());
      expect(ThoughtEchoDiscoveryService().isScanning, isA<bool>());
    });

    test('同步状态枚举完整性', () {
      // 验证所有同步状态都已定义
      const allStates = SyncStatus.values;
      
      expect(allStates.contains(SyncStatus.idle), isTrue);
      expect(allStates.contains(SyncStatus.packaging), isTrue);
      expect(allStates.contains(SyncStatus.sending), isTrue);
      expect(allStates.contains(SyncStatus.receiving), isTrue);
      expect(allStates.contains(SyncStatus.merging), isTrue);
      expect(allStates.contains(SyncStatus.completed), isTrue);
      expect(allStates.contains(SyncStatus.failed), isTrue);
    });

    test('网络常量验证', () {
      // 验证新的网络常量
      expect(defaultPort, equals(53318));
      expect(defaultMulticastGroup, equals('224.0.0.168'));
      expect(protocolVersion, equals('2.1'));
    });
  });
}
