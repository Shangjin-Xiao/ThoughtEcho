import '../../models/quote_model.dart';
import '../../models/generated_card.dart';

/// 抽象的卡片生成策略接口
abstract class CardGenerationStrategy {
  /// 生成卡片
  Future<GeneratedCard> generate({
    required Quote note,
    required String brandName,
    required String languageCode,
    String? customStyle,
    bool isRegeneration = false,
    CardType? excludeType,
  });
}
