import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';

void main() {
  group('同步功能基础测试', () {
    test('Device 模型基本测试', () {
      final device = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-fingerprint',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      // 验证设备属性
      expect(device.ip, '192.168.1.100');
      expect(device.alias, 'Test Device');
      expect(device.deviceType, DeviceType.mobile);
      expect(device.port, 53317);
      expect(device.version, '2.1');
      expect(device.download, true);
      expect(device.https, false);
    });

    test('Device 类基本功能测试', () {
      // 测试Device类的创建和基本功能
      final device = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-fingerprint',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      // 验证设备属性
      expect(device.ip, '192.168.1.100');
      expect(device.alias, 'Test Device');
      expect(device.deviceType, DeviceType.mobile);
      expect(device.port, 53317);
      expect(device.version, '2.1');
      expect(device.download, true);
      expect(device.https, false);
    });

    test('DeviceType 枚举测试', () {
      // 测试所有设备类型
      expect(DeviceType.values.contains(DeviceType.mobile), true);
      expect(DeviceType.values.contains(DeviceType.desktop), true);
      expect(DeviceType.values.contains(DeviceType.web), true);
      expect(DeviceType.values.contains(DeviceType.headless), true);
      expect(DeviceType.values.contains(DeviceType.server), true);
    });

    test('DiscoveryMethod 测试', () {
      // 测试发现方法
      const multicast = MulticastDiscovery();
      expect(multicast.toJson()['type'], 'multicast');

      const http = HttpDiscovery(ip: '192.168.1.1');
      expect(http.toJson()['type'], 'http');
      expect(http.toJson()['ip'], '192.168.1.1');

      const signaling = SignalingDiscovery(
        signalingServer: 'signal.server.com',
      );
      expect(signaling.toJson()['type'], 'signaling');
      expect(signaling.toJson()['signalingServer'], 'signal.server.com');
    });

    test('Device copyWith 测试', () {
      final original = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-fingerprint',
        alias: 'Original Device',
        deviceModel: 'Original Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      final updated = original.copyWith(alias: 'Updated Device', port: 53318);

      expect(updated.alias, 'Updated Device');
      expect(updated.port, 53318);
      expect(updated.ip, original.ip); // 未更改的属性应保持原值
      expect(updated.deviceType, original.deviceType);
    });
  });
}
