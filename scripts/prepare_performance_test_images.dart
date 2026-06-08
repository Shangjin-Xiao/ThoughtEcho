import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

const List<String> _sourceUrls = <String>[
  'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?fm=jpg&q=95',
  'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?fm=jpg&q=95',
  'https://images.unsplash.com/photo-1470770841072-f978cf4d019e?fm=jpg&q=95',
  'https://images.unsplash.com/photo-1447752875215-b2761acb3c5d?fm=jpg&q=95',
  'https://images.unsplash.com/photo-1519681393784-d120267933ba?fm=jpg&q=95',
];

const int _minimumPixels = 8 * 1000 * 1000;
const int _maximumPixels = 20 * 1000 * 1000;
const int _minimumEncodedBytes = 750 * 1024;

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln(
      'Usage: dart run scripts/prepare_performance_test_images.dart '
      '[output-directory]',
    );
    exitCode = 64;
    return;
  }

  final Directory outputDirectory = Directory(
    arguments.isEmpty ? 'assets' : arguments.single,
  );
  await outputDirectory.create(recursive: true);

  final HttpClient client = HttpClient()
    ..userAgent = 'ThoughtEcho Firebase performance test';
  try {
    for (int index = 0; index < _sourceUrls.length; index++) {
      final Uri uri = Uri.parse(_sourceUrls[index]);
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Image ${index + 1} returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final List<int> sourceBytes = await response.fold<List<int>>(
        <int>[],
        (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
      );
      final image.Image? decoded = image.decodeImage(
        Uint8List.fromList(sourceBytes),
      );
      if (decoded == null) {
        throw FormatException('Image ${index + 1} is not decodable: $uri');
      }
      final int pixels = decoded.width * decoded.height;
      if (pixels < _minimumPixels) {
        throw FormatException(
          'Image ${index + 1} is too small: '
          '${decoded.width}x${decoded.height}',
        );
      }

      image.Image benchmarkImage = decoded;
      if (pixels > _maximumPixels) {
        final double scale = math.sqrt(_maximumPixels / pixels);
        benchmarkImage = image.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: image.Interpolation.average,
        );
      }

      // Re-encoding removes provider-specific/progressive JPEG variants that
      // Android ImageDecoder may reject on Firebase virtual devices.
      final List<int> jpegBytes = image.encodeJpg(benchmarkImage, quality: 95);
      if (jpegBytes.length < _minimumEncodedBytes) {
        throw FormatException(
          'Image ${index + 1} encoded size is unexpectedly small: '
          '${jpegBytes.length} bytes',
        );
      }

      final File output = File(
        '${outputDirectory.path}/large_test_${index + 1}.jpg',
      );
      await output.writeAsBytes(jpegBytes, flush: true);
      stdout.writeln(
        '${output.path}: ${benchmarkImage.width}x${benchmarkImage.height}, '
        '${(jpegBytes.length / 1024 / 1024).toStringAsFixed(2)} MiB',
      );
    }
  } finally {
    client.close(force: true);
  }
}
