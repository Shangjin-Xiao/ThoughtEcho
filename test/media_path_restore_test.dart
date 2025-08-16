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
          'insert': {
            'image': '/app/documents/media/images/img1.png',
          }
        },
        {
          'insert': {
            'video': '/app/documents/media/videos/v1.mp4',
          }
        },
        {
          'insert': {
            'custom': {
              'audio': '/app/documents/media/audios/a1.mp3',
            }
          }
        },
        {'insert': 'text'}
      ];

      // 备份阶段: 绝对 -> 相对
      final toRelative = BackupService.testConvertDeltaMediaPaths(delta,
          appPath: appPath, toRelative: true);
      // 验证路径被裁剪
      String norm(dynamic v) => v.toString().replaceAll('\\', '/');
      expect(norm(toRelative[0]['insert']['image']), 'media/images/img1.png');
      expect(norm(toRelative[1]['insert']['video']), 'media/videos/v1.mp4');
      expect(norm(toRelative[2]['insert']['custom']['audio']),
          'media/audios/a1.mp3');

      // 还原阶段: 相对 -> 绝对
      final restored = BackupService.testConvertDeltaMediaPaths(toRelative,
          appPath: appPath, toRelative: false);
      expect(norm(restored[0]['insert']['image']),
          '/app/documents/media/images/img1.png');
      expect(norm(restored[1]['insert']['video']),
          '/app/documents/media/videos/v1.mp4');
      expect(norm(restored[2]['insert']['custom']['audio']),
          '/app/documents/media/audios/a1.mp3');
    });
  });
}
