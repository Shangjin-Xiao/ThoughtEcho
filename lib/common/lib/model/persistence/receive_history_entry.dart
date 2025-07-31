/// Receive history entry model
import '../file_type.dart';

class ReceiveHistoryEntry {
  final String id;
  final String fileName;
  final FileType fileType;
  final String? path;
  final bool savedToGallery;
  final bool isMessage;
  final int fileSize;
  final String senderAlias;
  final DateTime timestamp;

  const ReceiveHistoryEntry({
    required this.id,
    required this.fileName,
    required this.fileType,
    this.path,
    required this.savedToGallery,
    required this.isMessage,
    required this.fileSize,
    required this.senderAlias,
    required this.timestamp,
  });
}