/// Receive session state for LocalSend
import 'dart:async';
import '../../device.dart';
import '../../session_status.dart';
import 'receiving_file.dart';

class ReceiveSessionState {
  final String sessionId;
  final SessionStatus status;
  final Device sender;
  final String senderAlias;
  final Map<String, ReceivingFile> files;
  final int? startTime;
  final int? endTime;
  final String destinationDirectory;
  final String cacheDirectory;
  final bool saveToGallery;
  final Set<String> createdDirectories;
  final StreamController<Map<String, String>?>? responseHandler;
  final String? message;

  const ReceiveSessionState({
    required this.sessionId,
    required this.status,
    required this.sender,
    required this.senderAlias,
    required this.files,
    this.startTime,
    this.endTime,
    required this.destinationDirectory,
    required this.cacheDirectory,
    required this.saveToGallery,
    required this.createdDirectories,
    this.responseHandler,
    this.message,
  });

  ReceiveSessionState copyWith({
    String? sessionId,
    SessionStatus? status,
    Device? sender,
    String? senderAlias,
    Map<String, ReceivingFile>? files,
    int? startTime,
    int? endTime,
    String? destinationDirectory,
    String? cacheDirectory,
    bool? saveToGallery,
    Set<String>? createdDirectories,
    StreamController<Map<String, String>?>? responseHandler,
    String? message,
  }) {
    return ReceiveSessionState(
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      sender: sender ?? this.sender,
      senderAlias: senderAlias ?? this.senderAlias,
      files: files ?? this.files,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      destinationDirectory: destinationDirectory ?? this.destinationDirectory,
      cacheDirectory: cacheDirectory ?? this.cacheDirectory,
      saveToGallery: saveToGallery ?? this.saveToGallery,
      createdDirectories: createdDirectories ?? this.createdDirectories,
      responseHandler: responseHandler ?? this.responseHandler,
      message: message ?? this.message,
    );
  }
}