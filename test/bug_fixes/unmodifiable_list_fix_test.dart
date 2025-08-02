import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';

void main() {
  group('不可修改列表修复测试', () {
    test('Device 列表应该支持修改操作', () {
      // 创建一个设备列表
      final devices = <Device>[
        Device(
          signalingId: null,
          ip: '192.168.1.100',
          version: '2.1',
          port: 53317,
          https: false,
          fingerprint: 'test-device',
          alias: 'Test Device',
          deviceModel: 'Test Model',
          deviceType: DeviceType.mobile,
          download: true,
          discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
        ),
      ];

      // 验证列表支持修改操作
      expect(() => devices.clear(), returnsNormally);
      expect(() => devices.add(Device(
        signalingId: null,
        ip: '192.168.1.101',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-device2',
        alias: 'Test Device 2',
        deviceModel: 'Test Model',
        deviceType: DeviceType.desktop,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      )), returnsNormally);
    });

    test('从不可修改列表创建可修改副本', () {
      // 模拟不可修改列表
      final originalList = List<Device>.unmodifiable([
        Device(
          signalingId: null,
          ip: '192.168.1.100',
          version: '2.1',
          port: 53317,
          https: false,
          fingerprint: 'test-device',
          alias: 'Test Device',
          deviceModel: 'Test Model',
          deviceType: DeviceType.mobile,
          download: true,
          discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
        ),
      ]);

      // 验证原列表不可修改
      expect(() => originalList.clear(), throwsUnsupportedError);

      // 创建可修改副本
      final modifiableList = List<Device>.from(originalList);
      
      // 验证副本可修改
      expect(() => modifiableList.clear(), returnsNormally);
      expect(modifiableList.isEmpty, true);
      expect(originalList.isNotEmpty, true); // 原列表不受影响
    });
  });
}
