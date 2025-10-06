import 'dart:typed_data';

bool isDataUrl(String source) => source.startsWith('data:');

Uint8List? tryDecodeDataUrl(String source) {
  if (!isDataUrl(source)) {
    return null;
  }

  try {
    final uri = Uri.parse(source);
    if (!uri.isScheme('data')) {
      return null;
    }

    final data = uri.data;
    if (data == null) {
      return null;
    }

    return data.contentAsBytes();
  } catch (_) {
    return null;
  }
}
