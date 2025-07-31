/// Receiving file model for LocalSend
import '../../dto/file_dto.dart';
import '../../file_status.dart';

class ReceivingFile {
  final FileDto file;
  final FileStatus status;
  final String? token;
  final String? desiredName;
  final String? path;
  final bool savedToGallery;
  final String? errorMessage;

  const ReceivingFile({
    required this.file,
    required this.status,
    this.token,
    this.desiredName,
    this.path,
    required this.savedToGallery,
    this.errorMessage,
  });

  ReceivingFile copyWith({
    FileDto? file,
    FileStatus? status,
    String? token,
    String? desiredName,
    String? path,
    bool? savedToGallery,
    String? errorMessage,
  }) {
    return ReceivingFile(
      file: file ?? this.file,
      status: status ?? this.status,
      token: token ?? this.token,
      desiredName: desiredName ?? this.desiredName,
      path: path ?? this.path,
      savedToGallery: savedToGallery ?? this.savedToGallery,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}