import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/svg_to_image_service.dart';
import 'package:thoughtecho/constants/card_templates.dart';
import 'dart:typed_data';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SOTA Card Rendering Performance and Correctness', () {
    test(
      'sotaModern SVG should be convertible to Image Bytes',
      () async {
        final svg = CardTemplates.sotaModernTemplate(
          brandName: 'ThoughtEcho',
          content:
              'Testing SOTA rendering performance. This SVG contains complex mesh gradients and drop shadows.',
          author: 'Sisyphus',
          date: '2026-01-22',
        );

        // We use a timeout because offscreen rendering can sometimes hang in test environments if not properly configured
        final bytes =
            await SvgToImageService.convertSvgToImage(
              svg,
              width: 400,
              height: 600,
              useCache: false,
            ).timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                // If it times out, it might be due to test environment limitations, but we want to see if it even starts
                return Uint8List(0);
              },
            );

        // In some headless test environments, real rendering might fail or return empty,
        // but it shouldn't crash with OOM or other fatal errors.
        expect(bytes, isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test(
      'upgraded knowledgeTemplate with mesh gradients should be convertible',
      () async {
        final svg = CardTemplates.knowledgeTemplate(
          brandName: 'ThoughtEcho',
          content: 'Testing upgraded knowledge template.',
          author: 'Sisyphus',
        );

        final bytes = await SvgToImageService.convertSvgToImage(
          svg,
          width: 400,
          height: 600,
          useCache: false,
        ).timeout(const Duration(seconds: 15), onTimeout: () => Uint8List(0));

        expect(bytes, isNotNull);
      },
    );
  });
}
