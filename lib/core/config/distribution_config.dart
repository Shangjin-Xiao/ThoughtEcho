/// Represents the distribution channel / flavor of the app.
enum DistributionChannel {
  standard,
  play,
}

/// Compile-time and runtime distribution channel configuration.
abstract final class DistributionConfig {
  static const String _rawChannel = String.fromEnvironment(
    'DISTRIBUTION_CHANNEL',
    defaultValue: 'standard',
  );

  /// Current active distribution channel.
  static DistributionChannel get channel => _rawChannel == 'play'
      ? DistributionChannel.play
      : DistributionChannel.standard;

  /// Whether this build targets the Google Play Store.
  static bool get isPlayStore => channel == DistributionChannel.play;

  /// Whether this build targets standard distribution (website / GitHub release).
  static bool get isStandard => channel == DistributionChannel.standard;

  /// Whether in-app APK download & installation is supported.
  static bool get supportsApkSelfUpdate => isStandard;

  /// Whether requesting battery optimization exemption is allowed.
  static bool get supportsBatteryOptimizationExemption => isStandard;
}
