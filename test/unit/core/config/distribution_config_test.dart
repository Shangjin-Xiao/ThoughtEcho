import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/core/config/distribution_config.dart';

void main() {
  group('DistributionChannel', () {
    test('verifies standard channel capabilities', () {
      const channel = DistributionChannel.standard;
      expect(channel.isStandard, isTrue);
      expect(channel.isPlayStore, isFalse);
      expect(channel.supportsApkSelfUpdate, isTrue);
      expect(channel.supportsBatteryOptimizationExemption, isTrue);
    });

    test('verifies play channel capabilities', () {
      const channel = DistributionChannel.play;
      expect(channel.isStandard, isFalse);
      expect(channel.isPlayStore, isTrue);
      expect(channel.supportsApkSelfUpdate, isFalse);
      expect(channel.supportsBatteryOptimizationExemption, isFalse);
    });
  });

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
