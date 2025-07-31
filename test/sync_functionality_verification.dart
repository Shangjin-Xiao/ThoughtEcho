import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/sync_protocol/constants.dart';
import 'package:thoughtecho/services/sync_protocol/models/device_info.dart';
import 'package:thoughtecho/services/sync_protocol/models/file_transfer_dto.dart';

void main() {
  group('同步功能验证', () {
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
      
      // 验证状态数量
      expect(allStates.length, equals(7));
    });

    test('同步状态转换逻辑', () {
      // 验证状态转换的合理性
      const validTransitions = {
        SyncStatus.idle: [SyncStatus.packaging, SyncStatus.receiving],
        SyncStatus.packaging: [SyncStatus.sending, SyncStatus.failed],
        SyncStatus.sending: [SyncStatus.completed, SyncStatus.failed],
        SyncStatus.receiving: [SyncStatus.merging, SyncStatus.failed],
        SyncStatus.merging: [SyncStatus.completed, SyncStatus.failed],
        SyncStatus.completed: [SyncStatus.idle],
        SyncStatus.failed: [SyncStatus.idle],
      };

      // 验证每个状态都有定义的转换
      for (final status in SyncStatus.values) {
        expect(validTransitions.containsKey(status), isTrue,
            reason: '状态 $status 缺少转换定义');
      }
    });

    test('网络协议常量验证', () {
      // 验证协议常量的正确性
      expect(protocolVersion, equals('2.1'));
      expect(defaultPort, equals(53318));
      expect(defaultDiscoveryTimeout, equals(500));
      expect(defaultMulticastGroup, equals('224.0.0.168'));
    });

    test('API路径常量验证', () {
      // 验证API路径的正确性
      expect(ApiPaths.info, equals('/api/localsend/v2/info'));
      expect(ApiPaths.prepareUpload, equals('/api/localsend/v2/prepare-upload'));
      expect(ApiPaths.upload, equals('/api/localsend/v2/upload'));
      expect(ApiPaths.cancel, equals('/api/localsend/v2/cancel'));
    });

    test('设备类型枚举完整性', () {
      // 验证设备类型枚举
      const deviceTypes = DeviceType.values;
      
      expect(deviceTypes.contains(DeviceType.mobile), isTrue);
      expect(deviceTypes.contains(DeviceType.desktop), isTrue);
      expect(deviceTypes.contains(DeviceType.web), isTrue);
      expect(deviceTypes.contains(DeviceType.headless), isTrue);
      expect(deviceTypes.contains(DeviceType.server), isTrue);
    });

    test('协议类型枚举完整性', () {
      // 验证协议类型枚举
      const protocolTypes = ProtocolType.values;
      
      expect(protocolTypes.contains(ProtocolType.http), isTrue);
      expect(protocolTypes.contains(ProtocolType.https), isTrue);
    });

    test('传输状态枚举完整性', () {
      // 验证传输状态枚举
      const transferStates = TransferStatus.values;
      
      expect(transferStates.contains(TransferStatus.waiting), isTrue);
      expect(transferStates.contains(TransferStatus.preparing), isTrue);
      expect(transferStates.contains(TransferStatus.sending), isTrue);
      expect(transferStates.contains(TransferStatus.receiving), isTrue);
      expect(transferStates.contains(TransferStatus.completed), isTrue);
      expect(transferStates.contains(TransferStatus.failed), isTrue);
      expect(transferStates.contains(TransferStatus.cancelled), isTrue);
    });

    test('文件传输DTO序列化一致性', () {
      // 创建测试数据
      const fileInfo = FileInfo(
        id: 'test-file-123',
        fileName: 'test_backup.zip',
        size: 1024 * 1024, // 1MB
        hash: 'sha256-hash-value',
      );

      // 序列化和反序列化
      final json = fileInfo.toJson();
      final restored = FileInfo.fromJson(json);

      // 验证数据一致性
      expect(restored.id, equals(fileInfo.id));
      expect(restored.fileName, equals(fileInfo.fileName));
      expect(restored.size, equals(fileInfo.size));
      expect(restored.hash, equals(fileInfo.hash));
    });

    test('设备信息DTO序列化一致性', () {
      // 创建测试设备信息
      const deviceInfo = DeviceInfo(
        alias: 'ThoughtEcho测试设备',
        version: '2.1',
        deviceModel: 'Test Device Model',
        deviceType: DeviceType.mobile,
        fingerprint: 'unique-device-fingerprint',
        port: 53317,
        protocol: ProtocolType.http,
        download: true,
      );

      // 序列化和反序列化
      final json = deviceInfo.toJson();
      final restored = DeviceInfo.fromJson(json);

      // 验证数据一致性
      expect(restored.alias, equals(deviceInfo.alias));
      expect(restored.version, equals(deviceInfo.version));
      expect(restored.deviceModel, equals(deviceInfo.deviceModel));
      expect(restored.deviceType, equals(deviceInfo.deviceType));
      expect(restored.fingerprint, equals(deviceInfo.fingerprint));
      expect(restored.port, equals(deviceInfo.port));
      expect(restored.protocol, equals(deviceInfo.protocol));
      expect(restored.download, equals(deviceInfo.download));
    });

    test('网络设备URL生成', () {
      // 创建测试网络设备
      const deviceInfo = DeviceInfo(
        alias: 'Test Device',
        version: '2.1',
        deviceModel: 'Test Model',
        deviceType: DeviceType.desktop,
        fingerprint: 'test-fingerprint',
        port: 53317,
        protocol: ProtocolType.http,
        download: true,
      );

      const networkDevice = NetworkDevice(
        ip: '192.168.1.100',
        port: 53317,
        info: deviceInfo,
        https: false,
      );

      // 验证URL生成
      expect(networkDevice.baseUrl, equals('http://192.168.1.100:53317'));

      // 测试HTTPS设备
      const httpsDevice = NetworkDevice(
        ip: '192.168.1.101',
        port: 53318,
        info: deviceInfo,
        https: true,
      );

      expect(httpsDevice.baseUrl, equals('https://192.168.1.101:53318'));
    });

    test('传输会话状态管理', () {
      // 创建初始会话
      const fileInfo = FileInfo(
        id: 'session-file',
        fileName: 'session_test.zip',
        size: 2048,
      );

      const session = TransferSession(
        sessionId: 'test-session-123',
        remoteDeviceId: 'remote-device-456',
        status: TransferStatus.waiting,
        files: {'session-file': fileInfo},
        progress: 0.0,
      );

      // 测试状态更新
      final updatedSession = session.copyWith(
        status: TransferStatus.sending,
        progress: 0.5,
        fileTokens: {'session-file': 'upload-token-789'},
      );

      // 验证更新结果
      expect(updatedSession.status, equals(TransferStatus.sending));
      expect(updatedSession.progress, equals(0.5));
      expect(updatedSession.fileTokens?['session-file'], equals('upload-token-789'));
      
      // 验证未更新的字段保持不变
      expect(updatedSession.sessionId, equals(session.sessionId));
      expect(updatedSession.remoteDeviceId, equals(session.remoteDeviceId));
      expect(updatedSession.files, equals(session.files));
    });
  });
}
