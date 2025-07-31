import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/sync_protocol/models/device_info.dart';
import 'package:thoughtecho/services/sync_protocol/models/file_transfer_dto.dart';
import 'package:thoughtecho/services/sync_protocol/utils/api_routes.dart';

void main() {
  group('Sync Protocol Tests', () {
    test('DeviceInfo serialization', () {
      const deviceInfo = DeviceInfo(
        alias: 'Test Device',
        version: '2.1',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        fingerprint: 'test-fingerprint',
        port: 53317,
        protocol: ProtocolType.http,
        download: true,
      );

      final json = deviceInfo.toJson();
      final restored = DeviceInfo.fromJson(json);

      expect(restored.alias, equals(deviceInfo.alias));
      expect(restored.version, equals(deviceInfo.version));
      expect(restored.deviceType, equals(deviceInfo.deviceType));
      expect(restored.fingerprint, equals(deviceInfo.fingerprint));
    });

    test('FileInfo serialization', () {
      const fileInfo = FileInfo(
        id: 'test-file',
        fileName: 'test.zip',
        size: 1024,
        hash: 'test-hash',
      );

      final json = fileInfo.toJson();
      final restored = FileInfo.fromJson(json);

      expect(restored.id, equals(fileInfo.id));
      expect(restored.fileName, equals(fileInfo.fileName));
      expect(restored.size, equals(fileInfo.size));
      expect(restored.hash, equals(fileInfo.hash));
    });

    test('PrepareUploadRequest serialization', () {
      const deviceInfo = DeviceInfo(
        alias: 'Test Device',
        version: '2.1',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        fingerprint: 'test-fingerprint',
        port: 53317,
        protocol: ProtocolType.http,
        download: true,
      );

      const fileInfo = FileInfo(
        id: 'test-file',
        fileName: 'test.zip',
        size: 1024,
      );

      const request = PrepareUploadRequest(
        info: deviceInfo,
        files: {'test-file': fileInfo},
      );

      final json = request.toJson();
      final restored = PrepareUploadRequest.fromJson(json);

      expect(restored.info.alias, equals(deviceInfo.alias));
      expect(restored.files['test-file']?.fileName, equals(fileInfo.fileName));
    });

    test('API Routes generation', () {
      const deviceInfo = DeviceInfo(
        alias: 'Test Device',
        version: '2.1',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
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

      final infoUrl = ApiRoutes.info(networkDevice);
      expect(infoUrl, equals('http://192.168.1.100:53317/api/localsend/v2/info'));

      final prepareUrl = ApiRoutes.prepareUpload(networkDevice);
      expect(prepareUrl, equals('http://192.168.1.100:53317/api/localsend/v2/prepare-upload'));

      final uploadUrl = ApiRoutes.upload(
        networkDevice,
        sessionId: 'test-session',
        fileId: 'test-file',
        token: 'test-token',
      );
      expect(uploadUrl, contains('sessionId=test-session'));
      expect(uploadUrl, contains('fileId=test-file'));
      expect(uploadUrl, contains('token=test-token'));
    });

    test('TransferSession state management', () {
      const fileInfo = FileInfo(
        id: 'test-file',
        fileName: 'test.zip',
        size: 1024,
      );

      const session = TransferSession(
        sessionId: 'test-session',
        remoteDeviceId: 'remote-device',
        status: TransferStatus.waiting,
        files: {'test-file': fileInfo},
      );

      final updatedSession = session.copyWith(
        status: TransferStatus.sending,
        progress: 0.5,
      );

      expect(updatedSession.status, equals(TransferStatus.sending));
      expect(updatedSession.progress, equals(0.5));
      expect(updatedSession.sessionId, equals(session.sessionId));
      expect(updatedSession.files, equals(session.files));
    });
  });
}
