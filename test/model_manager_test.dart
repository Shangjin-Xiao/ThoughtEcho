import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/ai_model_manager.dart';

void main() {
  test('AIModelConfig structure', () {
    final config = AIModelManager.supportedModels.first;
    expect(config.id, 'minilm_v2');
    expect(config.type, AIModelType.embedding);
  });
}
