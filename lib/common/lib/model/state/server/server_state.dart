/// Server state model for LocalSend
import 'receive_session_state.dart';
import 'web_send_state.dart';

class ServerState {
  final ReceiveSessionState? session;
  final WebSendState? webSendState;
  final Map<String, int> pinAttempts;

  const ServerState({
    this.session,
    this.webSendState,
    this.pinAttempts = const {},
  });

  ServerState copyWith({
    ReceiveSessionState? session,
    WebSendState? webSendState,
    Map<String, int>? pinAttempts,
  }) {
    return ServerState(
      session: session ?? this.session,
      webSendState: webSendState ?? this.webSendState,
      pinAttempts: pinAttempts ?? this.pinAttempts,
    );
  }
}