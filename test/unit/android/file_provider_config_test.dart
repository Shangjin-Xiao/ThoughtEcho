import 'dart:io';

import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';

void main() {
  group('Android FileProvider config', () {
    test('declares cache FileProvider for Quill clipboard image sharing', () {
      final manifest = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );

      final provider = manifest.findAllElements('provider').singleWhere(
            (element) =>
                element.getAttribute('name', namespace: _androidNamespace) ==
                'androidx.core.content.FileProvider',
          );

      expect(
        provider.getAttribute('authorities', namespace: _androidNamespace),
        r'${applicationId}.fileprovider',
      );
      expect(
        provider.getAttribute('exported', namespace: _androidNamespace),
        'false',
      );
      expect(
        provider.getAttribute(
          'grantUriPermissions',
          namespace: _androidNamespace,
        ),
        'true',
      );

      final metaData = provider.findElements('meta-data').singleWhere(
            (element) =>
                element.getAttribute('name', namespace: _androidNamespace) ==
                'android.support.FILE_PROVIDER_PATHS',
          );

      expect(
        metaData.getAttribute('resource', namespace: _androidNamespace),
        '@xml/file_paths',
      );
    });

    test('allows FileProvider access to app cache files', () {
      final filePaths = XmlDocument.parse(
        File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync(),
      );

      final cachePath = filePaths.findAllElements('cache-path').single;

      expect(cachePath.getAttribute('name'), 'cache');
      expect(cachePath.getAttribute('path'), '.');
    });
  });

  group('Android ABI build variants', () {
    test('delegates rendering configuration to flavor placeholders', () {
      final manifest = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );
      final application = manifest.findAllElements('application').single;

      expect(
        application.getAttribute('vmSafeMode', namespace: _androidNamespace),
        r'${vmSafeMode}',
      );

      final metadataByName = {
        for (final element in application.findElements('meta-data'))
          element.getAttribute('name', namespace: _androidNamespace):
              element.getAttribute('value', namespace: _androidNamespace),
      };

      expect(
        metadataByName['io.flutter.embedding.android.EnableSoftwareRendering'],
        r'${enableSoftwareRendering}',
      );
      expect(
        metadataByName['io.flutter.embedding.android.EnableImpeller'],
        r'${enableImpeller}',
      );
    });

    test('defines isolated 64-bit and ARM32 compatibility flavors', () {
      final buildGradle = File('android/app/build.gradle').readAsStringSync();

      expect(buildGradle, contains("flavorDimensions 'abi'"));
      expect(buildGradle, contains('standard64 {'));
      expect(buildGradle, contains("abiFilters 'arm64-v8a'"));
      expect(buildGradle, contains("'vmSafeMode': 'false'"));
      expect(
        buildGradle,
        contains("'enableSoftwareRendering': 'false'"),
      );
      expect(buildGradle, contains("'enableImpeller': 'true'"));
      expect(buildGradle, contains('arm32Compat {'));
      expect(buildGradle, contains("abiFilters 'armeabi-v7a'"));
      expect(buildGradle, contains("'vmSafeMode': 'true'"));
      expect(buildGradle, contains("'enableSoftwareRendering': 'true'"));
      expect(buildGradle, contains("'enableImpeller': 'false'"));
    });

    test('lets release CI build either or both ABI flavors', () {
      final workflow = File(
        '.github/workflows/flutter-release-build.yml',
      ).readAsStringSync();

      expect(workflow, contains('build_variant:'));
      expect(workflow, contains('standard64'));
      expect(workflow, contains('arm32Compat'));
      expect(workflow, contains(r'--flavor "$FLAVOR"'));
      expect(
        workflow,
        contains('--android-project-arg=disable-abi-filtering=true'),
      );
      expect(workflow, contains(r'local OUTPUT_FLAVOR="${FLAVOR,,}"'));
      expect(
        workflow,
        contains(r'app-$OUTPUT_FLAVOR-$BUILD_MODE.apk'),
      );
    });

    test('requires configured release signing for non-debug artifacts', () {
      final workflow = File(
        '.github/workflows/flutter-release-build.yml',
      ).readAsStringSync();
      final buildGradle = File('android/app/build.gradle').readAsStringSync();

      expect(workflow, contains('验证正式签名配置'));
      expect(workflow, contains('set -euo pipefail'));
      expect(workflow, contains('missing_secrets=()'));
      expect(workflow, contains('keytool -list'));
      expect(workflow, contains('keytool -importkeystore'));
      expect(workflow, contains(r'-srckeypass "$KEY_PASSWORD"'));
      expect(workflow, isNot(contains('keytool -genkeypair')));
      expect(workflow, isNot(contains("KEYSTORE_PASSWORD || 'android'")));
      expect(workflow, isNot(contains("KEY_PASSWORD || 'android'")));
      expect(workflow, isNot(contains("KEY_ALIAS || 'androiddebugkey'")));

      expect(buildGradle, isNot(contains('使用debug签名')));
      expect(buildGradle, isNot(contains("keyAlias 'androiddebugkey'")));
      expect(buildGradle, contains('hasReleaseSigningConfig'));
      expect(
        buildGradle,
        contains('Release/profile builds require a complete '),
      );
      expect(
        buildGradle,
        contains('profile {\n            initWith debug\n'
            '            signingConfig signingConfigs.release'),
      );
    });

    test('keeps MMKV native load failures from aborting startup', () {
      final application = File(
        'android/app/src/main/kotlin/com/shangjin/thoughtecho/ThoughtEchoApplication.kt',
      ).readAsStringSync();

      expect(application, contains('catch (t: Throwable)'));
    });
  });
}
