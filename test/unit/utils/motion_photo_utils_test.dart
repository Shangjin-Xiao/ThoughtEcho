import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/motion_photo_utils.dart';

import '../../test_harness.dart';

final List<int> _motionPhotoMp4Trailer = <int>[
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x6D,
  0x70,
  0x34,
  0x32,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x08,
  0x6D,
  0x64,
  0x61,
  0x74,
];

Future<File> _createMotionPhotoFile(Directory directory) async {
  const minimalJpegBase64 =
      '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U'
      'HRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgN'
      'DRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy'
      'MjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAU'
      'EAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/AP/EABQQAQAAAAAAAAAAAAAA'
      'AAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8BP//E'
      'ABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8BP//Z';
  final file = File('${directory.path}/motion_photo.jpg');
  final imageBytes = base64Decode(minimalJpegBase64);
  final xmpBytes = utf8.encode(
    '<x:xmpmeta><rdf:Description '
    'GCamera:MotionPhoto="1" '
    'GCamera:MicroVideoOffset="${_motionPhotoMp4Trailer.length}" '
    '/></x:xmpmeta>',
  );

  await file.writeAsBytes(
    <int>[...imageBytes, ...xmpBytes, ..._motionPhotoMp4Trailer],
    flush: true,
  );
  return file;
}

Future<File> _createMotionPhotoFileWithFtypOnly(Directory directory) async {
  const minimalJpegBase64 =
      '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U'
      'HRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgN'
      'DRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy'
      'MjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAU'
      'EAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/AP/EABQQAQAAAAAAAAAAAAAA'
      'AAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8BP//E'
      'ABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8BP//Z';
  final file = File('${directory.path}/ftyp_only_motion_photo.jpg');
  final imageBytes = base64Decode(minimalJpegBase64);
  final padding = List<int>.filled(32, 0);

  await file.writeAsBytes(
    <int>[...imageBytes, ...padding, ..._motionPhotoMp4Trailer],
    flush: true,
  );
  return file;
}

Future<File> _createRegularImageFile(Directory directory) async {
  const minimalJpegBase64 =
      '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U'
      'HRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgN'
      'DRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy'
      'MjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAU'
      'EAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/AP/EABQQAQAAAAAAAAAAAAAA'
      'AAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8BP//E'
      'ABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8BP//Z';
  final file = File('${directory.path}/regular_image.jpg');
  await file.writeAsBytes(base64Decode(minimalJpegBase64), flush: true);
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(TestHarness.initialize);
  tearDownAll(TestHarness.tearDown);

  group('MotionPhotoUtils', () {
    test('detects Google motion photo using embedded metadata', () async {
      final tempDir = await TestHarness.createTempDirectory(
        'motion_photo_utils_detect',
      );
      addTearDown(() => TestHarness.deleteTempDirectory(tempDir));

      final file = await _createMotionPhotoFile(tempDir);
      final utils = createMotionPhotoUtils();

      final info = await utils.detect(file.path);

      expect(info, isNotNull);
      expect(info!.videoLength, _motionPhotoMp4Trailer.length);
    });

    test('detects motion photo using ftyp pattern fallback when XMP is absent',
        () async {
      final tempDir = await TestHarness.createTempDirectory(
        'motion_photo_utils_detect_ftyp',
      );
      addTearDown(() => TestHarness.deleteTempDirectory(tempDir));

      final file = await _createMotionPhotoFileWithFtypOnly(tempDir);
      final utils = createMotionPhotoUtils();

      final info = await utils.detect(file.path);

      expect(info, isNotNull);
      expect(info!.videoLength, _motionPhotoMp4Trailer.length);
    });

    test('returns null for non-motion photo images', () async {
      final tempDir = await TestHarness.createTempDirectory(
        'motion_photo_utils_detect_regular',
      );
      addTearDown(() => TestHarness.deleteTempDirectory(tempDir));

      final file = await _createRegularImageFile(tempDir);
      final utils = createMotionPhotoUtils();

      final info = await utils.detect(file.path);

      expect(info, isNull);
    });

    test('returns null gracefully for non-existent file path', () async {
      final utils = createMotionPhotoUtils();
      final info = await utils.detect('/non/existent/path/photo.jpg');

      expect(info, isNull);
    });

    test('returns null for files smaller than 32 bytes', () async {
      final tempDir = await TestHarness.createTempDirectory(
        'motion_photo_utils_detect_short',
      );
      addTearDown(() => TestHarness.deleteTempDirectory(tempDir));

      final file = File('${tempDir.path}/short.jpg');
      await file.writeAsBytes(List<int>.filled(10, 0), flush: true);
      final utils = createMotionPhotoUtils();

      final info = await utils.detect(file.path);

      expect(info, isNull);
    });

    test('extracts embedded motion photo video into a temporary mp4', () async {
      final tempDir = await TestHarness.createTempDirectory(
        'motion_photo_utils_extract',
      );
      addTearDown(() => TestHarness.deleteTempDirectory(tempDir));

      final file = await _createMotionPhotoFile(tempDir);
      final utils = createMotionPhotoUtils();
      final info = await utils.detect(file.path);

      final extractedPath = await utils.extractVideoToTemporaryFile(
        file.path,
        info: info,
      );
      addTearDown(() => utils.deleteTemporaryVideo(extractedPath));

      final extractedFile = File(extractedPath);
      expect(await extractedFile.exists(), isTrue);
      expect(await extractedFile.readAsBytes(), _motionPhotoMp4Trailer);
    });
  });
}
