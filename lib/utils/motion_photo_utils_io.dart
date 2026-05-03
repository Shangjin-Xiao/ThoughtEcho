import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'motion_photo_utils_base.dart';

const String _xmpStartMarker = '<x:xmpmeta';
const String _xmpEndMarker = '</x:xmpmeta>';
const List<String> _offsetKeys = <String>[
  'GCamera:MicroVideoOffset',
  'Item:Length',
];
const List<int> _ftypPattern = <int>[0x66, 0x74, 0x79, 0x70];

MotionPhotoUtils createMotionPhotoUtils() => const _IOMotionPhotoUtils();

class _IOMotionPhotoUtils extends MotionPhotoUtils {
  const _IOMotionPhotoUtils();

  @override
  Future<MotionPhotoInfo?> detect(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 32) {
      return null;
    }

    final attributes = _extractXmpAttributes(bytes);
    final xmpInfo = _extractVideoInfoFromAttributes(attributes, bytes.length);
    if (xmpInfo != null) {
      return xmpInfo;
    }

    final mp4HeaderOffset = _findLastPattern(bytes, _ftypPattern);
    if (mp4HeaderOffset == null || mp4HeaderOffset < 4) {
      return null;
    }

    final start = mp4HeaderOffset - 4;
    if (start >= bytes.length - 8) {
      return null;
    }

    return MotionPhotoInfo(videoStart: start, videoEnd: bytes.length);
  }

  @override
  Future<String> extractVideoToTemporaryFile(
    String filePath, {
    MotionPhotoInfo? info,
  }) async {
    final motionInfo = info ?? await detect(filePath);
    if (motionInfo == null) {
      throw StateError('The selected image is not a motion photo.');
    }

    final sourceFile = File(filePath);
    final tempDir = await getTemporaryDirectory();
    final outputDir = Directory(path.join(tempDir.path, 'motion_photos'));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final outputPath = path.join(
      outputDir.path,
      '${path.basenameWithoutExtension(filePath)}_'
      '${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    final randomAccessFile = await sourceFile.open();
    try {
      await randomAccessFile.setPosition(motionInfo.videoStart);
      final videoBytes = await randomAccessFile.read(motionInfo.videoLength);
      await File(outputPath).writeAsBytes(videoBytes, flush: true);
      return outputPath;
    } finally {
      await randomAccessFile.close();
    }
  }

  @override
  Future<void> deleteTemporaryVideo(String filePath) async {
    if (filePath.isEmpty) {
      return;
    }

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Map<String, String> _extractXmpAttributes(Uint8List bytes) {
  final buffer = latin1.decode(bytes, allowInvalid: true);
  final start = buffer.indexOf(_xmpStartMarker);
  if (start == -1) {
    return const <String, String>{};
  }

  final end = buffer.indexOf(_xmpEndMarker, start);
  if (end == -1) {
    return const <String, String>{};
  }

  final xmp = buffer.substring(start, end + _xmpEndMarker.length);
  final attributePattern = RegExp(
    r'''([A-Za-z0-9:_-]+)\s*=\s*["']([^"']*)["']''',
  );
  final attributes = <String, String>{};

  for (final match in attributePattern.allMatches(xmp)) {
    final key = match.group(1);
    final value = match.group(2);
    if (key != null && value != null) {
      attributes[key] = value;
    }
  }

  return attributes;
}

MotionPhotoInfo? _extractVideoInfoFromAttributes(
  Map<String, String> attributes,
  int fileSize,
) {
  if (attributes.isEmpty) {
    return null;
  }

  final hasMotionTag =
      attributes['GCamera:MotionPhoto'] == '1' ||
      attributes['GCamera:MicroVideo'] == '1' ||
      (attributes['Item:Mime']?.startsWith('video') ?? false);

  for (final key in _offsetKeys) {
    final raw = attributes[key];
    if (raw == null) {
      continue;
    }

    final offsetFromEnd = int.tryParse(raw);
    if (offsetFromEnd == null ||
        offsetFromEnd <= 0 ||
        offsetFromEnd >= fileSize) {
      continue;
    }

    if (!hasMotionTag && key == 'Item:Length' && offsetFromEnd < 16) {
      continue;
    }

    return MotionPhotoInfo(
      videoStart: fileSize - offsetFromEnd,
      videoEnd: fileSize,
    );
  }

  return null;
}

int? _findLastPattern(Uint8List bytes, List<int> pattern) {
  if (pattern.isEmpty || bytes.length < pattern.length) {
    return null;
  }

  for (int i = bytes.length - pattern.length; i >= 0; i--) {
    var matched = true;
    for (int j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return i;
    }
  }

  return null;
}
