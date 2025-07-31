/// Web send session model
import 'dart:async';

class WebSendSession {
  final String sessionId;
  final StreamController<bool>? responseHandler;
  final String ip;
  final Map<String, dynamic>? deviceInfo;

  const WebSendSession({
    required this.sessionId,
    this.responseHandler,
    required this.ip,
    this.deviceInfo,
  });

  WebSendSession copyWith({
    String? sessionId,
    StreamController<bool>? responseHandler,
    String? ip,
    Map<String, dynamic>? deviceInfo,
  }) {
    return WebSendSession(
      sessionId: sessionId ?? this.sessionId,
      responseHandler: responseHandler ?? this.responseHandler,
      ip: ip ?? this.ip,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
  }
}