import 'dart:io';

/// Test configuration for different environments
class TestConfig {
  /// Whether we're running in CI environment
  static bool get isCI =>
      Platform.environment['CI'] == 'true' ||
      Platform.environment['GITHUB_ACTIONS'] == 'true';

  /// Whether to run performance-sensitive tests
  static bool get runPerformanceTests => !isCI;

  /// Whether to run long-running tests
  static bool get runLongRunningTests => !isCI;

  /// Whether to run integration tests
  static bool get runIntegrationTests => !isCI;

  /// Timeout for CI tests (shorter for faster feedback)
  static Duration get ciTimeout => const Duration(seconds: 120);

  /// Timeout for local tests (longer for development)
  static Duration get localTimeout => const Duration(seconds: 300);

  /// Get appropriate timeout based on environment
  static Duration get testTimeout => isCI ? ciTimeout : localTimeout;

  /// Whether to enable verbose logging
  static bool get verboseLogging =>
      Platform.environment['VERBOSE_TESTS'] == 'true';

  /// Skip tests that are known to be problematic in CI
  static bool shouldSkipTest(String testName) {
    if (!isCI) return false;

    final problematicTests = [
      '测试标签筛选查询性能',
      'large file processing',
      'network timeout',
      'database migration performance',
    ];

    return problematicTests.any(
        (pattern) => testName.toLowerCase().contains(pattern.toLowerCase()));
  }
}
