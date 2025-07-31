import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import '../../common/model/device.dart';
import '../../common/util/simple_server.dart';
import 'provider/network/server/controller/receive_controller.dart';
import 'provider/network/server/controller/send_controller.dart';
import 'provider/network/server/server_utils.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
final _logger = Logger('LocalSendServer');

/// LocalSend server for ThoughtEcho note synchronization
class LocalSendServer {
  SimpleServer? _server;
  bool _isRunning = false;
  int _port = defaultPort;
  String _alias = 'ThoughtEcho';
  String _fingerprint = '';
  ReceiveController? _receiveController;
  SendController? _sendController;

  bool get isRunning => _isRunning;
  int get port => _port;
  String get alias => _alias;

  /// Start the LocalSend server
  Future<void> start({int? customPort}) async {
    if (_isRunning) {
      _logger.warning('Server is already running');
      return;
    }

    _port = customPort ?? defaultPort;
    _fingerprint = _generateFingerprint();

    try {
      _server = SimpleServer();
      
      // Create server utilities
      final serverUtils = ServerUtils(
        refFunc: () => throw UnimplementedError('Ref not implemented'),
        getState: () => throw UnimplementedError('State not implemented'),
        getStateOrNull: () => null,
        setState: (builder) => {},
      );

      // Initialize controllers
      _receiveController = ReceiveController(serverUtils);
      _sendController = SendController(serverUtils);

      // Install routes
      _receiveController!.installRoutes(
        router: _server!.router,
        alias: _alias,
        port: _port,
        https: false,
        fingerprint: _fingerprint,
        showToken: _generateToken(),
      );

      _sendController!.installRoutes(
        router: _server!.router,
        alias: _alias,
        fingerprint: _fingerprint,
      );

      // Start the server
      await _server!.start(port: _port);
      _isRunning = true;
      
      _logger.info('LocalSend server started on port $_port');
    } catch (e) {
      _logger.severe('Failed to start LocalSend server: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// Stop the LocalSend server
  Future<void> stop() async {
    if (!_isRunning || _server == null) {
      return;
    }

    try {
      await _server!.stop();
      _isRunning = false;
      _server = null;
      _receiveController = null;
      _sendController = null;
      
      _logger.info('LocalSend server stopped');
    } catch (e) {
      _logger.severe('Failed to stop LocalSend server: $e');
    }
  }

  /// Generate a unique fingerprint for this device
  String _generateFingerprint() {
    return _uuid.v4().replaceAll('-', '').substring(0, 16);
  }

  /// Generate a token for authentication
  String _generateToken() {
    return _uuid.v4().replaceAll('-', '').substring(0, 8);
  }

  /// Get server device information
  Device getDeviceInfo() {
    return Device(
      ip: _getLocalIp() ?? '127.0.0.1',
      port: _port,
      https: false,
      alias: _alias,
      version: protocolVersion,
      deviceModel: 'ThoughtEcho',
      deviceType: 'mobile',
      fingerprint: _fingerprint,
    );
  }

  /// Get local IP address
  String? _getLocalIp() {
    try {
      return NetworkInterface.list().then((interfaces) {
        for (final interface in interfaces) {
          for (final address in interface.addresses) {
            if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
              return address.address;
            }
          }
        }
        return null;
      }) as String?;
    } catch (e) {
      return null;
    }
  }
}
