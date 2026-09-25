import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/api_route_builder.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';

void main() {
  group('ApiRoute', () {
    group('v1 and v2 path getters', () {
      test('correctly constructs v1 and v2 paths for all routes', () {
        expect(ApiRoute.info.v1, '/api/localsend/v1/info');
        expect(ApiRoute.info.v2, '/api/localsend/v2/info');

        expect(ApiRoute.register.v1, '/api/localsend/v1/register');
        expect(ApiRoute.register.v2, '/api/localsend/v2/register');

        // prepareUpload has legacy 'send-request'
        expect(ApiRoute.prepareUpload.v1, '/api/localsend/v1/send-request');
        expect(ApiRoute.prepareUpload.v2, '/api/localsend/v2/prepare-upload');

        // upload has legacy 'send'
        expect(ApiRoute.upload.v1, '/api/localsend/v1/send');
        expect(ApiRoute.upload.v2, '/api/localsend/v2/upload');

        expect(ApiRoute.cancel.v1, '/api/localsend/v1/cancel');
        expect(ApiRoute.cancel.v2, '/api/localsend/v2/cancel');

        expect(ApiRoute.show.v1, '/api/localsend/v1/show');
        expect(ApiRoute.show.v2, '/api/localsend/v2/show');

        expect(
            ApiRoute.prepareDownload.v1, '/api/localsend/v1/prepare-download');
        expect(
            ApiRoute.prepareDownload.v2, '/api/localsend/v2/prepare-download');

        expect(ApiRoute.download.v1, '/api/localsend/v1/download');
        expect(ApiRoute.download.v2, '/api/localsend/v2/download');
      });
    });

    group('target', () {
      const baseDevice = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.0',
        port: 53317,
        https: false,
        fingerprint: 'fp123',
        alias: 'Test Device',
        deviceModel: 'TestModel',
        deviceType: DeviceType.desktop,
        download: true,
        discoveryMethods: {},
      );

      test('constructs HTTP URL for version 2.0 without query parameters', () {
        final url = ApiRoute.info.target(baseDevice);
        expect(url, 'http://192.168.1.100:53317/api/localsend/v2/info');
      });

      test('constructs HTTPS URL for version 1.0 with legacy route', () {
        final httpsV1Device = baseDevice.copyWith(
          https: true,
          version: '1.0',
        );
        final url = ApiRoute.prepareUpload.target(httpsV1Device);
        expect(
            url, 'https://192.168.1.100:53317/api/localsend/v1/send-request');
      });

      test('includes query parameters when provided', () {
        final url = ApiRoute.upload.target(
          baseDevice,
          query: {'token': 'abc123token', 'sessionId': '456'},
        );
        expect(
          url,
          'http://192.168.1.100:53317/api/localsend/v2/upload?token=abc123token&sessionId=456',
        );
      });
    });

    group('targetRaw', () {
      test('constructs HTTP URL for v2 route', () {
        final url = ApiRoute.register.targetRaw('10.0.0.5', 8080, false, '2.0');
        expect(url, 'http://10.0.0.5:8080/api/localsend/v2/register');
      });

      test('constructs HTTPS URL for v1 route', () {
        final url = ApiRoute.upload.targetRaw('10.0.0.5', 8080, true, '1.0');
        expect(url, 'https://10.0.0.5:8080/api/localsend/v1/send');
      });
    });
  });
}
