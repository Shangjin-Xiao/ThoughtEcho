/// Session status enumeration for sync operations.
enum LocalSendSessionStatus {
  waiting,
  declined,
  sending,
  finished,
  finishedWithErrors,
  canceledBySender,
  canceledByReceiver,
}

extension LocalSendSessionStatusX on LocalSendSessionStatus {
  bool get isFinished => this == LocalSendSessionStatus.finished;
  bool get isCanceled =>
      this == LocalSendSessionStatus.canceledBySender ||
      this == LocalSendSessionStatus.canceledByReceiver;
}