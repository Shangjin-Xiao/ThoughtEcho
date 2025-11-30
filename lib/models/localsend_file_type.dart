/// 文件类型枚举
enum FileType {
  /// 图片
  image,

  /// 视频
  video,

  /// 音频
  audio,

  /// 文档
  document,

  /// 文本
  text,

  /// 应用
  apk,

  /// 其他
  other,
}

extension FileTypeExtension on FileType {
  String get displayName {
    switch (this) {
      case FileType.image:
        return '图片';
      case FileType.video:
        return '视频';
      case FileType.audio:
        return '音频';
      case FileType.document:
        return '文档';
      case FileType.text:
        return '文本';
      case FileType.apk:
        return '应用';
      case FileType.other:
        return '其他';
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
