import 'dart:async';
import 'package:common/model/cross_file.dart';
import 'package:common/util/simple_server.dart';
import '../server_utils.dart';

class ReceiveController {
  final ServerUtils _serverUtils;

  ReceiveController(this._serverUtils);

  void installRoutes({
    required SimpleServerRouteBuilder router,
    required String alias,
    required int port,
    required bool https,
    required String fingerprint,
    required bool showToken,
  }) {
    // Implementation for installing receive routes
  }

  void acceptFileRequest(Map<String, String> fileNameMap) {
    // Implementation for accepting file requests
  }

  void declineFileRequest() {
    // Implementation for declining file requests
  }

  void setSessionDestinationDir(String destinationDirectory) {
    // Implementation for setting session destination directory
  }

  void setSessionSaveToGallery(bool saveToGallery) {
    // Implementation for setting save to gallery option
  }

  void cancelSession() {
    // Implementation for canceling session
  }

  void closeSession() {
    // Implementation for closing session
  }
}
