import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/safe_file_image.dart';

void main() {
  group('MissingMediaFileReporter.redact', () {
    test('正确处理标准路径格式', () {
      expect(
        MissingMediaFileReporter.redact(
            '/var/mobile/Containers/Data/image.png'),
        'image.png',
      );
      expect(
        MissingMediaFileReporter.redact(
            'C:\\Users\\User\\Documents\\photo.jpg'),
        'photo.jpg',
      );
    });

    test('正确处理包含 media/ 相对路径', () {
      expect(
        MissingMediaFileReporter.redact('/app/documents/media/images/test.jpg'),
        'media/images/test.jpg',
      );
    });

    test('正确处理空路径或无分隔符的纯文件名', () {
      expect(MissingMediaFileReporter.redact('solo_file.png'), 'solo_file.png');
      expect(MissingMediaFileReporter.redact(''), '');
    });
  });
}
