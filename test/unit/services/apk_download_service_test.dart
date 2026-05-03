import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:thoughtecho/services/apk_download_service.dart';

class MockDio extends Mock implements Dio {}

class MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {
  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    onDidReceiveNotificationResponse,
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {}
}

class MockPathProviderPlatform extends PathProviderPlatform {
  final String tempPath;
  MockPathProviderPlatform(this.tempPath);

  @override
  Future<String?> getExternalStoragePath() async {
    return '$tempPath/external';
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '$tempPath/documents';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDio mockDio;
  late MockFlutterLocalNotificationsPlugin mockNotifications;
  late Directory tempDir;
  late MockPathProviderPlatform mockPathProvider;

  setUp(() async {
    mockDio = MockDio();
    mockNotifications = MockFlutterLocalNotificationsPlugin();

    // Register fallback values for mocktail if needed
    registerFallbackValue(const NotificationDetails());

    ApkDownloadService.setDio(mockDio);
    ApkDownloadService.setNotificationsPlugin(mockNotifications);

    tempDir = await Directory.systemTemp.createTemp('apk_download_test');
    mockPathProvider = MockPathProviderPlatform(tempDir.path);
    PathProviderPlatform.instance = mockPathProvider;

    // Create required directories
    await Directory(
      '${tempDir.path}/external/Download',
    ).create(recursive: true);
    await Directory(
      '${tempDir.path}/documents/downloads',
    ).create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    ApkDownloadService.dispose();
  });

  group('ApkDownloadService', () {
    test(
      'cleanupApkFiles deletes only .apk files in download directory',
      () async {
        final downloadPath = '${tempDir.path}/external/Download';

        // Create some files
        final apk1 = File('$downloadPath/test1.apk');
        await apk1.writeAsString('test');
        final apk2 = File('$downloadPath/test2.APK'); // Case insensitive check
        await apk2.writeAsString('test');
        final other = File('$downloadPath/test.txt');
        await other.writeAsString('test');

        expect(await apk1.exists(), isTrue);
        expect(await apk2.exists(), isTrue);
        expect(await other.exists(), isTrue);

        await ApkDownloadService.cleanupApkFiles();

        expect(
          await apk1.exists(),
          isFalse,
          reason: 'test1.apk should be deleted',
        );
        expect(
          await apk2.exists(),
          isFalse,
          reason: 'test2.APK should be deleted',
        );
        expect(
          await other.exists(),
          isTrue,
          reason: 'test.txt should NOT be deleted',
        );
      },
    );

    test('cleanupApkFiles handles non-existent directory gracefully', () async {
      // Delete the external directory to simulate it not existing
      final externalDir = Directory('${tempDir.path}/external');
      if (await externalDir.exists()) {
        await externalDir.delete(recursive: true);
      }

      // Should not throw
      await ApkDownloadService.cleanupApkFiles();
    });

    test('dispose clears instances', () {
      ApkDownloadService.dispose();
    });

    test('getDownloadDirectory fallback logic', () async {
      final fallbackMock = MockPathProviderWithOptionalExternal(tempDir.path);
      PathProviderPlatform.instance = fallbackMock;

      final docsDownloadPath = '${tempDir.path}/documents/downloads';
      await Directory(docsDownloadPath).create(recursive: true);
      final apk = File('$docsDownloadPath/test.apk');
      await apk.writeAsString('test');

      await ApkDownloadService.cleanupApkFiles();

      expect(
        await apk.exists(),
        isFalse,
        reason: 'Should have cleaned up in documents/downloads',
      );
    });

    testWidgets('startDownload calls dio.download and shows notifications', (
      tester,
    ) async {
      final downloadPath =
          '${tempDir.path}/external/Download/ThoughtEcho_latest.apk';
      const apkUrl = 'https://example.com/app.apk';
      const version = '1.0.0';

      when(
        () => mockDio.download(
          any(),
          any(),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: apkUrl),
          statusCode: 200,
        ),
      );

      when(
        () => mockNotifications.show(any(), any(), any(), any()),
      ).thenAnswer((_) async {});

      when(
        () => mockNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >(),
      ).thenReturn(null);

      // Use a Scaffold with AppLocalizations to provide context
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () {
                    ApkDownloadService.startDownloadForTesting(
                      context,
                      apkUrl,
                      downloadPath,
                      version,
                    );
                  },
                  child: const Text('Test'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      verify(
        () => mockDio.download(
          apkUrl,
          downloadPath,
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).called(1);

      // Verify that notifications were shown (start and complete)
      verify(
        () => mockNotifications.show(any(), any(), any(), any()),
      ).called(greaterThanOrEqualTo(2));
    });
  });
}

class MockPathProviderWithOptionalExternal extends MockPathProviderPlatform {
  MockPathProviderWithOptionalExternal(String tempPath) : super(tempPath);

  @override
  Future<String?> getExternalStoragePath() async => null;
}
