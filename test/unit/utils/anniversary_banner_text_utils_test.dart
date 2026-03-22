import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/anniversary_banner_text_utils.dart';

void main() {
  group('formatAnniversaryBannerSubtitleForTile', () {
    test('将文案说明与日期拆成两行', () {
      expect(
        formatAnniversaryBannerSubtitleForTile(
          '感恩有你，一路同行 · 2025.3.23 - 2026.3.23',
        ),
        '感恩有你，一路同行\n2025.3.23 - 2026.3.23',
      );
    });

    test('没有分隔符时保持原文', () {
      expect(
        formatAnniversaryBannerSubtitleForTile('感恩有你，一路同行'),
        '感恩有你，一路同行',
      );
    });
  });
}
