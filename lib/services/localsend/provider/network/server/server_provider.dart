import 'dart:async';
import 'dart:io';

import '../../../constants.dart';
import 'package:common/isolate.dart';
import 'package:common/model/dto/multicast_dto.dart';
import 'package:common/model/cross_file.dart';
import 'package:common/model/state/server/server_state.dart';
import 'controller/receive_controller.dart';
import 'controller/send_controller.dart';
import 'server_utils.dart';
import '../../security_provider.dart';
import '../../settings_provider.dart';
import 'package:common/util/alias_generator.dart';
import 'package:common/util/simple_server.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('Server');

/// Default port constant for the server
const int defaultPort = 53317;

/// This provider runs the server and provides the current server state.
final serverProvider = NotifierProvider<ServerService, ServerState?>((ref) {
  return ServerService();
});

class ServerService extends Notifier<ServerState?> {
  late final _serverUtils = ServerUtils(
    refFunc: () => ref,
    getState: () => state!,
    getStateOrNull: () => state,
    setState: (builder) => state = builder(state),
  );

  late final _receiveController = ReceiveController(_serverUtils);
  late final _sendController = SendController(_serverUtils);

  @override
  ServerState? init() {
    return null;
  }

  /// Starts the server from user settings.
  Future<ServerState?> startServerFromSettings() async {
    final settings = ref.read(settingsProvider);
    return startServer(
      alias: settings.alias,
      port: settings.port,
      https: settings.https,
    );
  }

  /// Starts the server.
  Future<ServerState?> startServer({
    required String alias,
    required int port,
    required bool https,
  }) async {
    if (state != null) {
      _logger.info('Server already running.');
      return null;
    }

    alias = alias.trim();
    if (alias.isEmpty) {
      alias = generateRandomAlias();
    }

    if (port < 0 || port > 65535) {
      port = defaultPort;
    }

    final router = SimpleServerRouteBuilder();
    final fingerprint = ref.read(securityProvider).certificateHash;
    _receiveController.installRoutes(
      router: router,
      alias: alias,
      port: port,
      https: https,
      fingerprint: fingerprint,
      showToken: true,
    );
    _sendController.installRoutes(
      router: router,
      alias: alias,
      fingerprint: fingerprint,
    );

    _logger.info('Starting server...');

    final HttpServer httpServer;
    if (https) {
      final securityContext = ref.read(securityProvider);
      httpServer = await HttpServer.bindSecure(
        '0.0.0.0',
        port,
        SecurityContext()
          ..usePrivateKeyBytes(securityContext.privateKey.codeUnits)
          ..useCertificateChainBytes(securityContext.certificate.codeUnits),
      );
      _logger.info('Server started. (Port: $port, HTTPS only)');
    } else {
      httpServer = await HttpServer.bind(
        '0.0.0.0',
        port,
      );
      _logger.info('Server started. (Port: $port, HTTP only)');
    }

    final server = SimpleServer.start(server: httpServer, routes: router);

    final newServerState = ServerState(
      httpServer: server,
      alias: alias,
      port: port,
      https: https,
      session: null,
      webSendState: null,
      pinAttempts: {},
    );

    state = newServerState;
    return newServerState;
  }

  Future<void> stopServer() async {
    _logger.info('Stopping server...');
    await state?.httpServer.close();
    state = null;
    _logger.info('Server stopped.');
  }

  void acceptFileRequest(Map<String, String> fileNameMap) {
    _receiveController.acceptFileRequest(fileNameMap);
  }

  void declineFileRequest() {
    _receiveController.declineFileRequest();
  }

  void cancelSession() {
    _receiveController.cancelSession();
  }

  void closeSession() {
    _receiveController.closeSession();
  }

  Future<void> initializeWebSend(List<CrossFile> files) async {
    await _sendController.initializeWebSend(files: files);
  }

  void acceptWebSendRequest(String sessionId) {
    _sendController.acceptRequest(sessionId);
  }

  void declineWebSendRequest(String sessionId) {
    _sendController.declineRequest(sessionId);
  }
}
