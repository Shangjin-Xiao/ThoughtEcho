import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/optimized_image_loader_base.dart';

void main() {
  group('OptimizedImageLoaderBase', () {
    group('decodeDimensionFor', () {
      test('按逻辑尺寸乘以像素比换算成设备像素', () {
        expect(decodeDimensionFor(344, 2.0), 688);
      });

      test('尺寸过小时抬到下限，避免解成马赛克', () {
        expect(decodeDimensionFor(10, 2.0), minDecodeDimension);
      });

      test('尺寸过大时压到上限，避免单张解码撑爆内存', () {
        expect(decodeDimensionFor(4000, 3.0), maxDecodeDimension);
      });

      test('非法尺寸返回 null，表示不设解码上限', () {
        expect(decodeDimensionFor(0, 2.0), isNull);
        expect(decodeDimensionFor(-1, 2.0), isNull);
        expect(decodeDimensionFor(double.infinity, 2.0), isNull);
        expect(decodeDimensionFor(double.nan, 2.0), isNull);
      });

      test('像素比封顶后的解码宽度不会超过屏幕宽度 × 该上限', () {
        // 卡片宽度不会超过屏幕宽度；旗舰机的 dpr 会被调用方钳到 2.0。
        const screenWidth = 430.0;
        const cappedRatio = 2.0;
        final ceiling = (screenWidth * cappedRatio).round();

        for (final width in <double>[120, 344, 400, screenWidth]) {
          final decoded = decodeDimensionFor(width, cappedRatio);

          expect(decoded, isNotNull);
          expect(decoded! <= ceiling, isTrue, reason: 'width=$width');
        }
      });
    });

    group('decodeHeightBudgetFor', () {
      test('高度上限乘以解码宽度不超过总像素预算', () {
        for (final width in <int>[160, 688, 1032, 2048]) {
          final budget = decodeHeightBudgetFor(width);

          expect(budget, isNotNull);
          expect(
            budget! * width <= maxDecodePixels,
            isTrue,
            reason: 'width=$width',
          );
        }
      });

      test('常规照片与长截图的自然高度都在预算之内，不会被缩', () {
        // 卡片解码宽度约 688（344 逻辑宽 × 2 倍率）。
        const decodeWidth = 688;
        final budget = decodeHeightBudgetFor(decodeWidth)!;

        // 4:3 竖图
        expect(decodeWidth * 4 ~/ 3 < budget, isTrue);
        // 1080×24000 的十屏拼接长截图，等比到 688 宽后的高度
        expect((decodeWidth * 24000 / 1080).round() < budget, isTrue);
      });

      test('病态超长图会被预算挡住', () {
        const decodeWidth = 688;
        final budget = decodeHeightBudgetFor(decodeWidth)!;

        // 1080×100000：等比到 688 宽后约 63700 高，必须超出预算
        expect((decodeWidth * 100000 / 1080).round() > budget, isTrue);
      });

      test('没有宽度上限时也不设高度上限', () {
        expect(decodeHeightBudgetFor(null), isNull);
        expect(decodeHeightBudgetFor(0), isNull);
      });
    });

    group('wrapWithDecodeLimit', () {
      final base = MemoryImage(Uint8List.fromList(const [1, 2, 3]));

      test('没有解码上限时原样返回', () {
        expect(identical(wrapWithDecodeLimit(base, null, null), base), isTrue);
      });

      test('只给宽度时保持默认策略，高度按比例推算', () {
        final resized = wrapWithDecodeLimit(base, 800, null) as ResizeImage;

        expect(resized.width, 800);
        expect(resized.height, isNull);
        expect(resized.policy, ResizeImagePolicy.exact);
      });

      test('同时给宽高时必须用 fit 策略，否则长图会被拉变形', () {
        final resized = wrapWithDecodeLimit(base, 800, 1600) as ResizeImage;

        expect(resized.width, 800);
        expect(resized.height, 1600);
        expect(resized.policy, ResizeImagePolicy.fit);
      });
    });

    group('isDataUrl', () {
      test('returns true for valid data URL', () {
        const source =
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
        expect(isDataUrl(source), isTrue);
      });

      test('returns false for http URL', () {
        const source = 'http://example.com/image.png';
        expect(isDataUrl(source), isFalse);
      });

      test('returns false for https URL', () {
        const source = 'https://example.com/image.png';
        expect(isDataUrl(source), isFalse);
      });

      test('returns false for file URL', () {
        const source = 'file:///path/to/image.png';
        expect(isDataUrl(source), isFalse);
      });

      test('returns false for empty string', () {
        const source = '';
        expect(isDataUrl(source), isFalse);
      });

      test('returns false for string starting with data without colon', () {
        const source = 'database';
        expect(isDataUrl(source), isFalse);
      });
    });

    group('tryDecodeDataUrl', () {
      test('returns correct bytes for valid base64 data URL', () {
        // Base64 encoded "Hello World"
        const base64Data = 'SGVsbG8gV29ybGQ=';
        const source = 'data:text/plain;base64,$base64Data';

        final result = tryDecodeDataUrl(source);

        expect(result, isNotNull);
        expect(String.fromCharCodes(result!), 'Hello World');
      });

      test('returns correct bytes for valid percent-encoded data URL', () {
        // Percent encoded "Hello World"
        const source = 'data:text/plain,Hello%20World';

        final result = tryDecodeDataUrl(source);

        expect(result, isNotNull);
        expect(String.fromCharCodes(result!), 'Hello World');
      });

      test('returns null for non-data URL', () {
        const source = 'http://example.com/image.png';
        expect(tryDecodeDataUrl(source), isNull);
      });

      test('returns null for malformed data URL scheme', () {
        // Missing comma
        const source = 'data:text/plain;base64SGVsbG8gV29ybGQ=';
        expect(tryDecodeDataUrl(source), isNull);
      });

      test('returns null for invalid base64 content', () {
        // Invalid base64 characters
        const source = 'data:text/plain;base64,INVALID_BASE64_\$%';
        expect(tryDecodeDataUrl(source), isNull);
      });

      test('returns null for empty string', () {
        expect(tryDecodeDataUrl(''), isNull);
      });

      test('returns null for data URL without data', () {
        // data: is a valid scheme, but uri.data is parsed based on content.
        // 'data:' -> uri.data is empty but not null.
        // 'data:,' -> empty data.
        // Let's test a case where uri.data might be problematic or simply check empty data behavior.

        // 'data:' parses as scheme: data, path: empty. uri.data throws if scheme is not data.
        // But here scheme IS data.
        // uri.data handles parsing. If path is empty, it might be valid empty data.
        // Let's check a case that is technically valid URI but invalid data URI format for content.

        // If we pass something that Uri.parse accepts but doesn't have valid data part?
        // 'data://test' -> scheme: data, host: test.
        // uri.data getter: "The data of a data URI. The URI must have the scheme 'data' and no authority."
        // So 'data://test' has authority 'test'. accessing uri.data should throw or return null?
        // Documentation says: "If the URI does not have the 'data' scheme, or has an authority, this getter throws a StateError."
        // The implementation of tryDecodeDataUrl catches exceptions.

        const source = 'data://test';
        expect(tryDecodeDataUrl(source), isNull);
      });
    });
  });
}
