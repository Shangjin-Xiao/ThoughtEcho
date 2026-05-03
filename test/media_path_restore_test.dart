import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Media path convert in delta', () {
    test('relative -> absolute restore & absolute -> relative backup', () {
      const appPath = '/app/documents';
      // 构造包含 image / video / audio 的 Delta
      final delta = [
        {
          'insert': {'image': '/app/documents/media/images/img1.png'},
        },
        {
          'insert': {'video': '/app/documents/media/videos/v1.mp4'},
        },
        {
          'insert': {
            'custom': {'audio': '/app/documents/media/audios/a1.mp3'},
          },
        },
        {'insert': 'text'},
      ];

      // 备份阶段: 绝对 -> 相对
      final toRelative = BackupService.testConvertDeltaMediaPaths(
        delta,
        appPath: appPath,
        toRelative: true,
      );
      // 验证路径被裁剪
      String norm(dynamic v) => v.toString().replaceAll('\\', '/');
      expect(norm(toRelative[0]['insert']['image']), 'media/images/img1.png');
      expect(norm(toRelative[1]['insert']['video']), 'media/videos/v1.mp4');
      expect(
        norm(toRelative[2]['insert']['custom']['audio']),
        'media/audios/a1.mp3',
      );

      // 还原阶段: 相对 -> 绝对
      final restored = BackupService.testConvertDeltaMediaPaths(
        toRelative,
        appPath: appPath,
        toRelative: false,
      );
      expect(
        norm(restored[0]['insert']['image']),
        '/app/documents/media/images/img1.png',
      );
      expect(
        norm(restored[1]['insert']['video']),
        '/app/documents/media/videos/v1.mp4',
      );
      expect(
        norm(restored[2]['insert']['custom']['audio']),
        '/app/documents/media/audios/a1.mp3',
      );
    });

    test('cross-platform path handling - ZIP uses forward slashes', () {
      // 测试备份时生成的相对路径应该统一使用正斜杠
      // 注意：此测试在非 Windows 平台上运行，验证逻辑正确性
      // 实际 Windows 平台上 path.relative 会生成带 \ 的路径
      // 然后 _convertSingleMediaPath 会将 \ 转换为 /

      // 使用 Unix 风格路径测试（模拟 _convertSingleMediaPath 的输出行为）
      const unixAppPath = '/home/user/Documents/ThoughtEcho';
      final unixDelta = [
        {
          'insert': {
            'image': '/home/user/Documents/ThoughtEcho/media/images/photo.jpg',
          },
        },
      ];

      final toRelativeResult = BackupService.testConvertDeltaMediaPaths(
        unixDelta,
        appPath: unixAppPath,
        toRelative: true,
      );
      // 验证生成的相对路径使用正斜杠
      final relativePath = toRelativeResult[0]['insert']['image'] as String;
      expect(
        relativePath.contains(r'\'),
        isFalse,
        reason: '相对路径应该使用正斜杠，便于跨平台兼容',
      );
      expect(relativePath, 'media/images/photo.jpg');

      // 测试还原时能正确处理来自其他平台的路径
      final crossPlatformDelta = [
        {
          'insert': {'image': 'media/images/photo.jpg'},
        },
      ];

      // 在 Unix 上还原
      final restoredUnix = BackupService.testConvertDeltaMediaPaths(
        crossPlatformDelta,
        appPath: unixAppPath,
        toRelative: false,
      );
      final restoredUnixPath = restoredUnix[0]['insert']['image'] as String;
      // 路径应该被正确转换
      expect(restoredUnixPath.contains('media'), isTrue);
      expect(restoredUnixPath.contains('photo.jpg'), isTrue);
    });

    test('relative path with forward slash is correctly handled', () {
      // 测试从 ZIP 中提取的相对路径（使用正斜杠）能正确转换为绝对路径
      const appPath = '/app/documents';
      final deltaWithForwardSlash = [
        {
          'insert': {'image': 'media/images/photo.jpg'},
        },
        {
          'insert': {'video': 'media/videos/clip.mp4'},
        },
      ];

      final restored = BackupService.testConvertDeltaMediaPaths(
        deltaWithForwardSlash,
        appPath: appPath,
        toRelative: false,
      );

      String norm(dynamic v) => v.toString().replaceAll('\\', '/');
      expect(
        norm(restored[0]['insert']['image']),
        '/app/documents/media/images/photo.jpg',
      );
      expect(
        norm(restored[1]['insert']['video']),
        '/app/documents/media/videos/clip.mp4',
      );
    });
  });

  group('Quote delta field detection', () {
    test('supports snake_case and camelCase keys', () {
      expect(
        BackupService.testResolveQuoteDeltaField({'delta_content': '{}'}),
        'delta_content',
      );
      expect(
        BackupService.testResolveQuoteDeltaField({'deltaContent': '{}'}),
        'deltaContent',
      );
      expect(
        BackupService.testResolveQuoteDeltaField({'content': 'x'}),
        isNull,
      );
    });

    test('prefers delta_content when both keys present', () {
      expect(
        BackupService.testResolveQuoteDeltaField({
          'delta_content': '{"preferred":true}',
          'deltaContent': '{"other":true}',
        }),
        'delta_content',
      );
    });

    test('handles empty and null quotes', () {
      expect(BackupService.testResolveQuoteDeltaField({}), isNull);
      expect(
        BackupService.testResolveQuoteDeltaField({'other_field': 'value'}),
        isNull,
      );
    });
  });

  group('Delta structure variations', () {
    test('handles Map-type Delta (Quill Delta as Map)', () {
      const appPath = '/app/documents';
      // Some Quill Delta payloads are Map instead of List
      final deltaMap = {
        'ops': [
          {
            'insert': {'image': '/app/documents/media/images/photo.png'},
          },
          {'insert': 'caption\n'},
        ],
      };

      // 备份: 绝对 -> 相对
      final toRelative = BackupService.testConvertDeltaMediaPaths(
        deltaMap,
        appPath: appPath,
        toRelative: true,
      );
      expect(toRelative, isA<Map>());
      final ops = (toRelative as Map)['ops'] as List;
      String norm(dynamic v) => v.toString().replaceAll('\\', '/');
      expect(norm(ops[0]['insert']['image']), 'media/images/photo.png');

      // 还原: 相对 -> 绝对
      final restored = BackupService.testConvertDeltaMediaPaths(
        toRelative,
        appPath: appPath,
        toRelative: false,
      );
      final restoredOps = (restored as Map)['ops'] as List;
      expect(
        norm(restoredOps[0]['insert']['image']),
        '/app/documents/media/images/photo.png',
      );
    });

    test('handles nested custom blocks with audio', () {
      const appPath = '/app/documents';
      final deltaWithCustom = [
        {
          'insert': {
            'custom': {
              'type': 'audio-player',
              'audio': '/app/documents/media/audios/recording.m4a',
            },
          },
        },
      ];

      final toRelative = BackupService.testConvertDeltaMediaPaths(
        deltaWithCustom,
        appPath: appPath,
        toRelative: true,
      );
      String norm(dynamic v) => v.toString().replaceAll('\\', '/');
      expect(
        norm(toRelative[0]['insert']['custom']['audio']),
        'media/audios/recording.m4a',
      );

      final restored = BackupService.testConvertDeltaMediaPaths(
        toRelative,
        appPath: appPath,
        toRelative: false,
      );
      expect(
        norm(restored[0]['insert']['custom']['audio']),
        '/app/documents/media/audios/recording.m4a',
      );
    });

    test('handles mixed media types in single Delta', () {
      const appPath = '/app/documents';
      final mixedDelta = [
        {'insert': 'Title\n'},
        {
          'insert': {'image': '/app/documents/media/images/pic1.jpg'},
        },
        {'insert': 'Description\n'},
        {
          'insert': {'video': '/app/documents/media/videos/clip.mp4'},
        },
        {
          'insert': {
            'custom': {'audio': '/app/documents/media/audios/sound.mp3'},
          },
        },
        {'insert': 'End\n'},
      ];

      final toRelative = BackupService.testConvertDeltaMediaPaths(
        mixedDelta,
        appPath: appPath,
        toRelative: true,
      );
      String norm(dynamic v) => v.toString().replaceAll('\\', '/');
      expect(norm(toRelative[1]['insert']['image']), 'media/images/pic1.jpg');
      expect(norm(toRelative[3]['insert']['video']), 'media/videos/clip.mp4');
      expect(
        norm(toRelative[4]['insert']['custom']['audio']),
        'media/audios/sound.mp3',
      );

      // Verify text content is preserved
      expect(toRelative[0]['insert'], 'Title\n');
      expect(toRelative[2]['insert'], 'Description\n');
      expect(toRelative[5]['insert'], 'End\n');
    });

    test('preserves non-app paths unchanged', () {
      const appPath = '/app/documents';
      // External or web URLs should not be modified
      final externalDelta = [
        {
          'insert': {'image': 'https://example.com/image.png'},
        },
        {
          'insert': {'video': '/other/path/video.mp4'},
        },
      ];

      final toRelative = BackupService.testConvertDeltaMediaPaths(
        externalDelta,
        appPath: appPath,
        toRelative: true,
      );
      // Paths not under appPath should remain unchanged
      expect(toRelative[0]['insert']['image'], 'https://example.com/image.png');
      expect(toRelative[1]['insert']['video'], '/other/path/video.mp4');
    });
  });
}
