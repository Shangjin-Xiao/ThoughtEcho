# Technical Design Specification: Google Play Multi-Channel Isolation & Compliance

**Status**: Aligned & Drafted (EGM Protocol)
**Target Branch**: `feat/google-play-flavor`
**Target Application**: ThoughtEcho (Flutter Multiplatform)

---

## 1. Executive Summary & Goals
This specification establishes a robust multi-channel distribution architecture for ThoughtEcho to achieve 100% compliance with Google Play Developer Policies while preserving all existing self-update, background sync, and battery optimization capabilities for standalone (website/GitHub) releases.

### Key Compliance Requirements
1. **Zero Device & Network Abuse**: Completely strip `REQUEST_INSTALL_PACKAGES` and APK download/install routines from the Google Play build.
2. **Battery Optimization Policy Compliance**: Strip `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` and runtime whitelist requests from the Google Play build.
3. **Photo Picker Mandate Compliance**: Strip `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, and `READ_EXTERNAL_STORAGE` from the Google Play build, relying entirely on Android Photo Picker and Storage Access Framework.
4. **Android App Bundle (AAB)**: Produce signed `.aab` bundles for Play Store submission.
5. **Zero Regression for Standalone**: Website and GitHub APK releases retain 100% of existing functionality.
6. **Single Public Repository**: All code lives openly in the public repo; signing keys and credentials remain secure in GitHub Actions Secrets.

---

## 2. Technical Architecture & Stress-Tested Mitigations

### 2.1 Gradle Flavor Architecture
To avoid flavor dimension matrix explosions with existing ABI splits, we simplify the build dimensions:
- **Dimension**: `distribution`
  - `standard` (default): For GitHub / website APK distributions.
  - `play`: For Google Play Store AAB distributions.
- **Manifest Merger (`src/play/AndroidManifest.xml`)**:
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <manifest xmlns:android="http://schemas.android.com/apk/res/android"
      xmlns:tools="http://schemas.android.com/tools">

      <!-- Remove permissions prohibited or heavily restricted by Google Play -->
      <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" tools:node="remove" />
      <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" tools:node="remove" />
      <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" tools:node="remove" />
      <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" tools:node="remove" />
      <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" tools:node="remove" />
      <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" tools:node="remove" />
  </manifest>
  ```

### 2.2 Dart Distribution Abstraction (`lib/core/config/distribution_config.dart`)
We establish a zero-overhead compile-time & runtime abstraction:
```dart
enum DistributionChannel { standard, play }

abstract final class DistributionConfig {
  static const String _rawChannel = String.fromEnvironment(
    'DISTRIBUTION_CHANNEL',
    defaultValue: 'standard',
  );

  static DistributionChannel get channel =>
      _rawChannel == 'play' ? DistributionChannel.play : DistributionChannel.standard;

  static bool get isPlayStore => channel == DistributionChannel.play;
  static bool get isStandard => channel == DistributionChannel.standard;

  /// Whether direct in-app APK download & installation is supported
  static bool get supportsApkSelfUpdate => isStandard;

  /// Whether requesting battery optimization exemption is allowed
  static bool get supportsBatteryOptimizationExemption => isStandard;
}
```

### 2.3 Runtime Call Isolation (Crash Prevention)
- **`smart_push_permissions.dart`**:
  ```dart
  if (!DistributionConfig.supportsBatteryOptimizationExemption) {
    return false; // Safely return without touching permission_handler
  }
  ```
- **`update_dialog.dart`**:
  When an update is detected:
  - If `DistributionConfig.isPlayStore`:
    Launch `market://details?id=com.shangjin.thoughtecho` with fallback to `https://play.google.com/store/apps/details?id=com.shangjin.thoughtecho`.
  - If `DistributionConfig.isStandard`:
    Launch `ApkDownloadService.downloadAndInstallApk` (existing behavior).

---

## 3. Implementation Plan
1. **Phase 1**: Create `android/app/src/play/AndroidManifest.xml` and configure `flavorDimensions "distribution"` in `android/app/build.gradle`.
2. **Phase 2**: Add `DistributionConfig` in `lib/core/config/distribution_config.dart` with comprehensive unit tests.
3. **Phase 3**: Wire guards into `smart_push_permissions.dart`, `smart_push_settings_page_basic_sections.dart`, and `update_dialog.dart`.
4. **Phase 4**: Add GitHub Actions workflow for building release AAB.
