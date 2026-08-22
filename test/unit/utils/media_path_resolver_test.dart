import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/media_path_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const iosOldContainer =
      '/var/mobile/Containers/Data/Application/AAAA-1111/Documents';
  const iosNewContainer =
      '/var/mobile/Containers/Data/Application/BBBB-2222/Documents';
  const androidDocs = '/data/user/0/com.shangjin.thoughtecho/app_flutter';

  group('mediaRelativeTail', () {
    test('识别各平台绝对路径中的媒体尾段', () {
      expect(
        MediaPathResolver.mediaRelativeTail(
          '$iosOldContainer/media/images/a.jpg',
        ),
        'media/images/a.jpg',
      );
      expect(
        MediaPathResolver.mediaRelativeTail('$androidDocs/media/videos/v.mp4'),
        'media/videos/v.mp4',
      );
      expect(
        MediaPathResolver.mediaRelativeTail(
          r'C:\Users\me\Documents\media\audios\a.mp3',
        ),
        'media/audios/a.mp3',
      );
      expect(
        MediaPathResolver.mediaRelativeTail('media/images/a.jpg'),
        'media/images/a.jpg',
      );
    });

    test('取最靠近文件名的 media 段，避免上层同名目录误截', () {
      expect(
        MediaPathResolver.mediaRelativeTail(
          '/home/media/images/docs/media/images/a.jpg',
        ),
        'media/images/a.jpg',
      );
    });

    test('无法识别的路径返回 null', () {
      expect(MediaPathResolver.mediaRelativeTail(''), isNull);
      expect(MediaPathResolver.mediaRelativeTail('/tmp/photo.jpg'), isNull);
      // media 下的未知子目录不参与同步，不做重定基
      expect(
        MediaPathResolver.mediaRelativeTail('/x/media/html/page.html'),
        isNull,
      );
      expect(
        MediaPathResolver.mediaRelativeTail('/x/media/images/../../etc/passwd'),
        isNull,
      );
    });
  });

  group('resolveToLocal', () {
    test('iOS 容器 UUID 变化后重定基到当前容器', () {
      expect(
        MediaPathResolver.resolveToLocal(
          '$iosOldContainer/media/images/a.jpg',
          iosNewContainer,
        ),
        '$iosNewContainer/media/images/a.jpg',
      );
    });

    test('安卓路径同步到 iOS 后重定基', () {
      expect(
        MediaPathResolver.resolveToLocal(
          '$androidDocs/media/images/a.jpg',
          iosNewContainer,
        ),
        '$iosNewContainer/media/images/a.jpg',
      );
    });

    test('Windows 分隔符路径在 POSIX 端也能重定基', () {
      expect(
        MediaPathResolver.resolveToLocal(
          r'C:\Users\me\Documents\media\images\a.jpg',
          iosNewContainer,
        ),
        '$iosNewContainer/media/images/a.jpg',
      );
    });

    test('备份包里的相对路径解析为本机绝对路径', () {
      expect(
        MediaPathResolver.resolveToLocal(
          'media/images/a.jpg',
          iosNewContainer,
        ),
        '$iosNewContainer/media/images/a.jpg',
      );
    });

    test('已是本机路径时保持不变', () {
      const local = '$iosNewContainer/media/images/a.jpg';
      expect(MediaPathResolver.resolveToLocal(local, iosNewContainer), local);
    });

    test('file:// URI 会被还原为文件路径', () {
      expect(
        MediaPathResolver.resolveToLocal(
          'file://$iosOldContainer/media/images/a.jpg',
          iosNewContainer,
        ),
        '$iosNewContainer/media/images/a.jpg',
      );
    });

    test('非媒体路径保持原样，不做猜测拼接', () {
      const external = '/storage/emulated/0/DCIM/photo.jpg';
      expect(
        MediaPathResolver.resolveToLocal(external, iosNewContainer),
        external,
      );
    });
  });

  group('rebaseDelta', () {
    test('重写 image/video/custom.audio 三类嵌入并标记已改写', () {
      final delta = json.decode(json.encode([
        {
          'insert': {'image': '$iosOldContainer/media/images/a.jpg'},
        },
        {
          'insert': {'video': '$iosOldContainer/media/videos/v.mp4'},
        },
        {
          'insert': {
            'custom': {'audio': '$iosOldContainer/media/audios/a.mp3'},
          },
        },
        {'insert': '正文\n'},
      ]));

      final result = MediaPathResolver.rebaseDelta(delta, iosNewContainer);
      expect(result.changed, isTrue);

      final rebased = result.delta as List;
      expect(
        rebased[0]['insert']['image'],
        '$iosNewContainer/media/images/a.jpg',
      );
      expect(
        rebased[1]['insert']['video'],
        '$iosNewContainer/media/videos/v.mp4',
      );
      expect(
        rebased[2]['insert']['custom']['audio'],
        '$iosNewContainer/media/audios/a.mp3',
      );
      expect(rebased[3]['insert'], '正文\n');
    });

    test('路径已经正确时 changed 为 false，调用方可跳过写回', () {
      final delta = json.decode(json.encode([
        {
          'insert': {'image': '$iosNewContainer/media/images/a.jpg'},
        },
        {'insert': '正文\n'},
      ]));

      final result = MediaPathResolver.rebaseDelta(delta, iosNewContainer);
      expect(result.changed, isFalse);
    });
  });
}
