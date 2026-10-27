import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/device_identity_manager.dart';
import 'package:thoughtecho/services/localsend/secure_transport.dart';

void main() {
  test('rejects an HTTP peer before sending any request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'sessionId': 'remote-session', 'files': {}}));
      await request.response.close();
    });
    final provider = LocalSendProvider();
    addTearDown(provider.dispose);

    await expectLater(
      provider.startSession(
        target: Device.empty.copyWith(
          ip: '127.0.0.1',
          port: server.port,
          version: '2.1',
          https: false,
        ),
        files: [],
      ),
      throwsA(isA<StateError>()),
    );
    expect(requests, 0);
  });

  test('rejects a substituted certificate before sending control data',
      () async {
    final identity = await DeviceIdentityManager.I.getLocalSendIdentity();
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      identity.securityContext,
    );
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.response.close();
    });
    final peer = Device.empty.copyWith(
      ip: '127.0.0.1',
      port: server.port,
      version: '2.1',
      https: true,
      fingerprint: '0' * 64,
    );
    final provider = LocalSendProvider();
    addTearDown(provider.dispose);
    await expectLater(provider.startSession(target: peer, files: []),
        throwsA(isA<Exception>()));
    final dio = LocalSendTransport.createDio(peer, BaseOptions());
    addTearDown(() => dio.close(force: true));
    await expectLater(
      dio.post(
          'https://127.0.0.1:${server.port}/api/thoughtecho/v1/sync-intent',
          data: {'alias': 'Sender'}),
      throwsA(isA<DioException>()),
    );
    expect(requests, 0);
  });

  test('neither peer client follows an HTTPS redirect to HTTP', () async {
    final identity = await DeviceIdentityManager.I.getLocalSendIdentity();
    final trap = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => trap.close(force: true));
    var leakedRequests = 0;
    trap.listen((request) async {
      leakedRequests++;
      await request.response.close();
    });
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      identity.securityContext,
    );
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.temporaryRedirect
        ..headers.set(
            HttpHeaders.locationHeader, 'http://127.0.0.1:${trap.port}/stolen');
      await request.response.close();
    });
    final peer = Device.empty.copyWith(
      ip: '127.0.0.1',
      port: server.port,
      version: '2.1',
      https: true,
      fingerprint: identity.fingerprint,
    );
    final client = LocalSendTransport.createClient(peer);
    addTearDown(client.close);
    final url = 'https://127.0.0.1:${server.port}/upload?token=synthetic';
    final response = await client.post(Uri.parse(url), body: 'private bytes');
    final dio = LocalSendTransport.createDio(
        peer,
        BaseOptions(
          validateStatus: (_) => true,
        ));
    addTearDown(() => dio.close(force: true));
    final approval = await dio.post(url, data: {'alias': 'Sender'});

    expect(response.statusCode, HttpStatus.temporaryRedirect);
    expect(approval.statusCode, HttpStatus.temporaryRedirect);
    expect(leakedRequests, 0);
  });
}
