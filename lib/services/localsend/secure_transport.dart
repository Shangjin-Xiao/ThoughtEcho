import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'models/device.dart';

/// An in-memory identity shared by discovery, the receiver and the pairing UI.
/// A new process gets a new key; users verify the full fingerprint before sending.
class LocalSendIdentity {
  final SecurityContext securityContext;
  final String fingerprint;

  LocalSendIdentity._(this.securityContext, this.fingerprint);

  static Future<LocalSendIdentity> generate() async {
    final material = await Isolate.run(() {
      final keys = CryptoUtils.generateRSAKeyPair();
      final privateKey = keys.privateKey as RSAPrivateKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'ThoughtEcho'},
        privateKey,
        keys.publicKey as RSAPublicKey,
      );
      final certificate =
          X509Utils.generateSelfSignedCertificate(privateKey, csr, 365);
      final der = base64Decode(certificate
          .replaceAll('-----BEGIN CERTIFICATE-----', '')
          .replaceAll('-----END CERTIFICATE-----', '')
          .replaceAll(RegExp(r'\s'), ''));
      // iOS requires PKCS12 for usePrivateKeyBytes. The bundle stays in memory;
      // no password encryption is needed for this transient key container.
      final bundle = Pkcs12Utils.generatePkcs12(
        CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
        [certificate],
        password: '',
        keyPbe: 'NONE',
        certPbe: 'NONE',
      );
      return (bundle, sha256.convert(der).toString());
    });
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(material.$1, password: '')
      ..usePrivateKeyBytes(material.$1, password: '');
    return LocalSendIdentity._(context, material.$2);
  }
}

/// All peer requests use HTTPS, pin the certificate and refuse redirects.
/// The pin must be compared with the receiving device through the pairing UI;
/// UDP discovery is an unauthenticated hint, not a trust source.
class LocalSendTransport {
  static void requireSecurePeer(Device peer) {
    if (!peer.https ||
        peer.ip == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(peer.fingerprint)) {
      throw StateError('Peer does not support verified secure sync');
    }
  }

  static HttpClient createHttpClient(Device peer) {
    requireSecurePeer(peer);
    // No system roots: even a CA-signed certificate must match the paired pin.
    return HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (certificate, host, port) =>
          host == peer.ip &&
          port == peer.port &&
          sha256.convert(certificate.der).toString() == peer.fingerprint;
  }

  static http.Client createClient(Device peer) =>
      _PeerClient(IOClient(createHttpClient(peer)));

  static Dio createDio(Device peer, BaseOptions options) {
    requireSecurePeer(peer);
    options.followRedirects = false;
    return Dio(options)
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => createHttpClient(peer),
      );
  }
}

class _PeerClient extends http.BaseClient {
  final http.Client _client;

  _PeerClient(this._client);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.followRedirects = false;
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
