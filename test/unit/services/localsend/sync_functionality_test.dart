import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';
import 'package:thoughtecho/services/localsend/localsend_server.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';
import 'package:thoughtecho/utils/path_security_utils.dart';

void main() {
  group('同步功能测试', () {
    test('端口配置测试', () {
      // 验证端口配置正确
      expect(defaultPort, 53320);
      expect(defaultMulticastGroup, '224.0.0.170');
    });

    test('LocalSend服务器初始化测试', () async {
      final server = LocalSendServer();
      expect(server.isRunning, false);
      expect(server.port, defaultPort);
    });

    test('LocalSend发送服务初始化测试', () {
      final provider = LocalSendProvider();
      expect(provider.sessions, isEmpty);
    });

    test('设备发现服务初始化测试', () {
      final discoveryService = ThoughtEchoDiscoveryService();
      expect(discoveryService.isScanning, false);
      expect(discoveryService.devices, isEmpty);
    });

    test('设备模型创建测试', () {
      final device = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: protocolVersion,
        port: defaultPort,
        https: false,
        fingerprint: 'test-device',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      expect(device.ip, '192.168.1.100');
      expect(device.port, defaultPort);
      expect(device.version, protocolVersion);
      expect(device.download, true);
    });

    test('路径安全性清理测试', () {
      expect(
        PathSecurityUtils.sanitizeZipEntryName('normal_file.txt'),
        'normal_file.txt',
      );
      expect(
        PathSecurityUtils.sanitizeZipEntryName('/etc/passwd'),
        'etc/passwd',
      );
      expect(
        PathSecurityUtils.sanitizeZipEntryName('\\windows\\system32\\file.txt'),
        'windows/system32/file.txt',
      );
    });

    group('网络功能测试', () {
      test('端口可用性测试', () async {
        // 测试端口是否可以绑定
        try {
          final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
          expect(socket.port, greaterThan(0));
          await socket.close();
        } catch (e) {
          fail('无法绑定到任何端口: $e');
        }
      });

      test('UDP套接字测试', () async {
        try {
          final socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
          );
          expect(socket.port, greaterThan(0));
          socket.close();
        } catch (e) {
          fail('无法创建UDP套接字: $e');
        }
      });
    });

    group('协议兼容性测试', () {
      test('协议版本测试', () {
        expect(protocolVersion, '2.1');
        expect(peerProtocolVersion, '1.0');
        expect(fallbackProtocolVersion, '1.0');
      });

      test('发现超时配置测试', () {
        expect(defaultDiscoveryTimeout, 30000);
      });
    });
  });
}
