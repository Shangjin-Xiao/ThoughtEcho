import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/localsend/models/file_dto.dart';
import 'package:thoughtecho/services/localsend/models/file_type.dart';

void main() {
  group('LocalSend 核心组件测试', () {
    test('Constants 测试', () {
      // 测试常量定义
      expect(protocolVersion, '2.1');
      expect(defaultPort, 53320);
  expect(defaultDiscoveryTimeout, 30000);
    });

    test('FileDto 测试', () {
      // 测试文件DTO
      const fileDto = FileDto(
        id: 'file-123',
        fileName: 'test.txt',
        size: 1024,
        fileType: FileType.text,
        hash: 'abc123',
        preview: null,
        metadata: null,
        legacy: false,
      );

      expect(fileDto.id, 'file-123');
      expect(fileDto.fileName, 'test.txt');
      expect(fileDto.size, 1024);
      expect(fileDto.fileType, FileType.text);
    });

    test('FileType 枚举测试', () {
      // 测试文件类型枚举
      expect(FileType.values.contains(FileType.text), true);
      expect(FileType.values.contains(FileType.image), true);
      expect(FileType.values.contains(FileType.video), true);
      expect(FileType.values.contains(FileType.pdf), true);
      expect(FileType.values.contains(FileType.apk), true);
      expect(FileType.values.contains(FileType.other), true);
    });

    test('Device 与 LocalSend 集成测试', () {
      // 创建一个LocalSend兼容的设备
      final device = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: protocolVersion,
        port: defaultPort,
        https: false,
        fingerprint: 'localsend-device',
        alias: 'LocalSend Device',
        deviceModel: 'Test Device',
        deviceType: DeviceType.desktop,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      // 验证设备符合LocalSend协议要求
      expect(device.version, protocolVersion);
      expect(device.port, defaultPort);
      expect(device.download, true);

      // 测试传输方法
      final transmissionMethods = device.transmissionMethods;
      expect(transmissionMethods.isNotEmpty, true);
      expect(transmissionMethods.contains(TransmissionMethod.http), true);
    });

    test('MulticastDiscovery 测试', () {
      const discovery1 = MulticastDiscovery();
      const discovery2 = MulticastDiscovery();

      // 测试相等性
      expect(discovery1 == discovery2, true);
      expect(discovery1.hashCode, discovery2.hashCode);

      // 测试JSON序列化
      final json = discovery1.toJson();
      expect(json['type'], 'multicast');

      final fromJson = DiscoveryMethod.fromJson(json);
      expect(fromJson, isA<MulticastDiscovery>());
    });

    test('HttpDiscovery 测试', () {
      const discovery1 = HttpDiscovery(ip: '192.168.1.1');
      const discovery2 = HttpDiscovery(ip: '192.168.1.1');
      const discovery3 = HttpDiscovery(ip: '192.168.1.2');

      // 测试相等性
      expect(discovery1 == discovery2, true);
      expect(discovery1 == discovery3, false);

      // 测试JSON序列化
      final json = discovery1.toJson();
      expect(json['type'], 'http');
      expect(json['ip'], '192.168.1.1');

      final fromJson = DiscoveryMethod.fromJson(json);
      expect(fromJson, isA<HttpDiscovery>());
      expect((fromJson as HttpDiscovery).ip, '192.168.1.1');
    });

    test('复杂Device创建和使用测试', () {
      // 创建具有多种发现方法的设备
      final device = Device(
        signalingId: 'signal-456',
        ip: '10.0.0.5',
        version: '2.1',
        port: 53318,
        https: true,
        fingerprint: 'complex-device-fingerprint',
        alias: 'Complex Test Device',
        deviceModel: 'Advanced Model',
        deviceType: DeviceType.server,
        download: true,
        discoveryMethods: <DiscoveryMethod>{
          const MulticastDiscovery(),
          const HttpDiscovery(ip: '10.0.0.5'),
          const SignalingDiscovery(signalingServer: 'signal.example.com'),
        },
      );

      // 验证设备属性
      expect(device.discoveryMethods.length, 3);
      expect(device.https, true);
      expect(device.deviceType, DeviceType.server);

      // 验证传输方法包含HTTP和WebRTC
      final methods = device.transmissionMethods;
      expect(methods.contains(TransmissionMethod.http), true);
      expect(methods.contains(TransmissionMethod.webrtc), true);

      // 测试JSON往返转换
      final json = device.toJson();
      final deviceFromJson = Device.fromJson(json);
      expect(deviceFromJson.ip, device.ip);
      expect(deviceFromJson.alias, device.alias);
      expect(deviceFromJson.discoveryMethods.length,
          device.discoveryMethods.length);
    });
  });
}
