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
    tearDown(DistributionConfig.resetDebugOverrides);

    test('defaults to standard distribution channel', () {
      expect(DistributionConfig.channel, equals(DistributionChannel.standard));
      expect(DistributionConfig.isStandard, isTrue);
      expect(DistributionConfig.isPlayStore, isFalse);
      expect(DistributionConfig.supportsApkSelfUpdate, isTrue);
      expect(DistributionConfig.supportsBatteryOptimizationExemption, isTrue);
    });

    test('resolveChannel prefers explicit play dart-define', () {
      expect(
        DistributionConfig.resolveChannel(rawChannel: 'play', flavor: null),
        equals(DistributionChannel.play),
      );
    });

    test('resolveChannel falls back to Flutter appFlavor == play', () {
      expect(
        DistributionConfig.resolveChannel(
          rawChannel: 'standard',
          flavor: 'play',
        ),
        equals(DistributionChannel.play),
      );
    });

    test('resolveChannel safely defaults to standard when flavor is null', () {
      expect(
        DistributionConfig.resolveChannel(rawChannel: 'standard', flavor: null),
        equals(DistributionChannel.standard),
      );
      expect(
        DistributionConfig.resolveChannel(
          rawChannel: 'standard',
          flavor: 'standard',
        ),
        equals(DistributionChannel.standard),
      );
    });

    test('debugAppFlavorOverride activates Play Store capabilities', () {
      DistributionConfig.debugAppFlavorOverride = 'play';
      expect(DistributionConfig.channel, equals(DistributionChannel.play));
      expect(DistributionConfig.isPlayStore, isTrue);
      expect(DistributionConfig.isStandard, isFalse);
      expect(DistributionConfig.supportsApkSelfUpdate, isFalse);
      expect(DistributionConfig.supportsBatteryOptimizationExemption, isFalse);
    });
  });
}
