import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/local_embedding_service.dart';

void main() {
  test('LocalEmbeddingService instantiation', () {
    final service = LocalEmbeddingService();
    expect(service.isInitialized, false);
  });
}
