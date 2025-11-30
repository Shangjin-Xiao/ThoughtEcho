import 'device.dart';
import 'session_status.dart';
import 'sending_file.dart';
// import 'receive_session_state.dart'; // Removed - not needed

class SendSessionState {
  final String sessionId;
  final String? remoteSessionId; // v2
  final bool background;

  final SessionStatus status;

  final Device target;
  final Map<String, SendingFile> files; // file id as key

  final int? startTime;

  final int? endTime;

  final List<SendingTask>? sendingTasks; // used to cancel tasks
  final String? errorMessage;

  const SendSessionState({
    required this.sessionId,
    required this.remoteSessionId,
    required this.background,
    required this.status,
    required this.target,
    required this.files,
    required this.startTime,
    required this.endTime,
    required this.sendingTasks,
    required this.errorMessage,
  });

  SendSessionState copyWith({
    String? sessionId,
    String? remoteSessionId,
    bool? background,
    SessionStatus? status,
    Device? target,
    Map<String, SendingFile>? files,
    int? startTime,
    int? endTime,
    List<SendingTask>? sendingTasks,
    String? errorMessage,
  }) {
    return SendSessionState(
      sessionId: sessionId ?? this.sessionId,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
      background: background ?? this.background,
      status: status ?? this.status,
      target: target ?? this.target,
      files: files ?? this.files,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sendingTasks: sendingTasks ?? this.sendingTasks,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Custom toString() to avoid printing the bytes.
  /// The default toString() does not respect the overridden toString() of
  /// SendingFile.
  @override
  String toString() {
    return 'SendSessionState(sessionId: $sessionId, remoteSessionId: $remoteSessionId, background: $background, status: $status, target: $target, files: $files, startTime: $startTime, endTime: $endTime, sendingTasks: $sendingTasks, errorMessage: $errorMessage)';
  }
}

class SendingTask {
  final int isolateIndex;
  final String taskId; // Changed to String to match isolate_actions.dart

  SendingTask({required this.isolateIndex, required this.taskId});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SendingTask &&
        other.isolateIndex == isolateIndex &&
        other.taskId == taskId;
  }

  @override
  int get hashCode => Object.hash(isolateIndex, taskId);

  @override
  String toString() {
    return 'SendingTask(isolateIndex: $isolateIndex, taskId: $taskId)';
  }
}
