import '../gen_l10n/app_localizations.dart';

/// 文件类型枚举（UI 文案通过 l10n 获取）
enum FileType {
  image,
  video,
  audio,
  document,
  text,
  apk,
  other,
}

extension FileTypeExtension on FileType {
  /// 获取本地化名称（在 UI 层调用并传入 l10n）
  String localized(AppLocalizations l10n) {
    switch (this) {
      case FileType.image:
        return l10n.fileTypeImage;
      case FileType.video:
        return l10n.fileTypeVideo;
      case FileType.audio:
        return l10n.fileTypeAudio;
      case FileType.document:
        return l10n.fileTypeDocument;
      case FileType.text:
        return l10n.fileTypeText;
      case FileType.apk:
        return l10n.fileTypeApplication;
      case FileType.other:
        return l10n.fileTypeOther;
    }
  }

  /// 根据文件扩展名判断文件类型
  static FileType fromExtension(String extension) {
    final ext = extension.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'].contains(ext)) {
      return FileType.image;
    } else if ([
      'mp4',
      'avi',
      'mov',
      'wmv',
      'flv',
      'mkv',
      'webm',
    ].contains(ext)) {
      return FileType.video;
    } else if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].contains(ext)) {
      return FileType.audio;
    } else if ([
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
    ].contains(ext)) {
      return FileType.document;
    } else if (['txt', 'md', 'json', 'xml', 'csv'].contains(ext)) {
      return FileType.text;
    } else if (ext == 'apk') {
      return FileType.apk;
    } else {
      return FileType.other;
    }
  }
}
