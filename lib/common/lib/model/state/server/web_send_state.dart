/// Web send state for LocalSend
import '../send/web/web_send_session.dart';
import '../send/web/web_send_file.dart';

class WebSendState {
  final Map<String, WebSendSession> sessions;
  final Map<String, WebSendFile> files;
  final bool autoAccept;
  final String? pin;
  final Map<String, int> pinAttempts;

  const WebSendState({
    required this.sessions,
    required this.files,
    required this.autoAccept,
    this.pin,
    required this.pinAttempts,
  });

  WebSendState copyWith({
    Map<String, WebSendSession>? sessions,
    Map<String, WebSendFile>? files,
    bool? autoAccept,
    String? pin,
    Map<String, int>? pinAttempts,
  }) {
    return WebSendState(
      sessions: sessions ?? this.sessions,
      files: files ?? this.files,
      autoAccept: autoAccept ?? this.autoAccept,
      pin: pin ?? this.pin,
      pinAttempts: pinAttempts ?? this.pinAttempts,
    );
  }
}