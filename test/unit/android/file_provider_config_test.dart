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
                element.getAttribute(
                  'name',
                  namespace: _androidNamespace,
                ) ==
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
                element.getAttribute(
                  'name',
                  namespace: _androidNamespace,
                ) ==
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

  group('Android ARM32 startup compatibility', () {
    test('keeps manifest-level rendering fallbacks for old ARM32 devices', () {
      final manifest = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );
      final application = manifest.findAllElements('application').single;

      expect(
        application.getAttribute('vmSafeMode', namespace: _androidNamespace),
        'true',
      );

      final metadataByName = {
        for (final element in application.findElements('meta-data'))
          element.getAttribute('name', namespace: _androidNamespace):
              element.getAttribute('value', namespace: _androidNamespace),
      };

      expect(
        metadataByName['io.flutter.embedding.android.EnableSoftwareRendering'],
        'true',
      );
      expect(metadataByName['io.flutter.embedding.android.EnableImpeller'],
          'false');
    });

    test('keeps native startup guards for ARM32 and MMKV load failures', () {
      final application = File(
        'android/app/src/main/kotlin/com/shangjin/thoughtecho/ThoughtEchoApplication.kt',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/shangjin/thoughtecho/MainActivity.kt',
      ).readAsStringSync();

      expect(application, contains('catch (t: Throwable)'));
      expect(application, contains('isArm32Device()'));
      expect(application, contains('debug.egl.hw'));
      expect(mainActivity, contains('isArm32Device()'));
      expect(mainActivity, contains('FLAG_HARDWARE_ACCELERATED'));
    });
  });
}
