import 'dart:async';
import 'package:common/model/cross_file.dart';
import 'package:common/util/simple_server.dart';
import '../server_utils.dart';

class SendController {
  final ServerUtils _serverUtils;

  SendController(this._serverUtils);

  void installRoutes({
    required SimpleServerRouteBuilder router,
    required String alias,
    required String fingerprint,
  }) {
    // Implementation for installing send routes
  }

  Future<void> initializeWebSend({required List<CrossFile> files}) async {
    // Implementation for initializing web send
  }

  void acceptRequest(String sessionId) {
    // Implementation for accepting requests
  }

  void declineRequest(String sessionId) {
    // Implementation for declining requests
  }
}
