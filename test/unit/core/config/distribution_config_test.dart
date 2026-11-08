import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/core/config/distribution_config.dart';

void main() {
  group('DistributionConfig', () {
    test('defaults to standard distribution channel', () {
      expect(DistributionConfig.channel, equals(DistributionChannel.standard));
      expect(DistributionConfig.isStandard, isTrue);
      expect(DistributionConfig.isPlayStore, isFalse);
      expect(DistributionConfig.supportsApkSelfUpdate, isTrue);
      expect(DistributionConfig.supportsBatteryOptimizationExemption, isTrue);
    });
  });
}
