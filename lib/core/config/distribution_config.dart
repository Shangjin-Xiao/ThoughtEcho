import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show appFlavor;

/// Represents the distribution channel / flavor of the app.
enum DistributionChannel {
  standard,
  play;

  bool get isPlayStore => this == DistributionChannel.play;
  bool get isStandard => this == DistributionChannel.standard;
  bool get supportsApkSelfUpdate => this == DistributionChannel.standard;
  bool get supportsBatteryOptimizationExemption =>
      this == DistributionChannel.standard;
}

/// Compile-time and runtime distribution channel configuration.
abstract final class DistributionConfig {
  static const String _rawChannel = String.fromEnvironment(
    'DISTRIBUTION_CHANNEL',
    defaultValue: 'standard',
  );

  @visibleForTesting
  static DistributionChannel? debugChannelOverride;

  @visibleForTesting
  static String? debugAppFlavorOverride;

  @visibleForTesting
  static void resetDebugOverrides() {
    debugChannelOverride = null;
    debugAppFlavorOverride = null;
  }

  /// Resolves the effective [DistributionChannel] from compile-time defines
  /// and Flutter's runtime [appFlavor].
  @visibleForTesting
  static DistributionChannel resolveChannel({
    String rawChannel = _rawChannel,
    String? flavor,
  }) {
    if (rawChannel == 'play' || flavor == 'play') {
      return DistributionChannel.play;
    }
    return DistributionChannel.standard;
  }

  /// Current active distribution channel.
  static DistributionChannel get channel =>
      debugChannelOverride ??
      resolveChannel(
        rawChannel: _rawChannel,
        flavor: debugAppFlavorOverride ?? appFlavor,
      );

  /// Whether this build targets the Google Play Store.
  static bool get isPlayStore => channel.isPlayStore;

  /// Whether this build targets standard distribution (website / GitHub release).
  static bool get isStandard => channel.isStandard;

  /// Whether in-app APK download & installation is supported.
  static bool get supportsApkSelfUpdate => channel.supportsApkSelfUpdate;

  /// Whether requesting battery optimization exemption is allowed.
  static bool get supportsBatteryOptimizationExemption =>
      channel.supportsBatteryOptimizationExemption;
}
