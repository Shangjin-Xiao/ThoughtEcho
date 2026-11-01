import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/unified_media_import_dialog.dart';

import '../../test_harness.dart';

// Exercise Dio's native HTTP adapter and automatic gzip decoding against only
// the synthetic loopback server, instead of Flutter's default HTTP 400 fake.
class _LocalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  late HttpServer server;
  late HttpOverrides? originalOverrides;
  late String fileName;
  late List<String> imported;
  final detachedSockets = <Socket>[];

  setUp(() async {
    await TestHarness.initialize();
    originalOverrides = HttpOverrides.current;
    HttpOverrides.global = _LocalHttpOverrides();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fileName = 'url_import_${DateTime.now().microsecondsSinceEpoch}.mp3';
    imported = [];
  });

  tearDown(() async {
    for (final socket in detachedSockets) {
      socket.destroy();
    }
    detachedSockets.clear();
    await server.close(force: true);
    HttpOverrides.global = originalOverrides;
    // Also clean up the baseline's leftover output after a failed regression.
    await for (final entry in Directory.systemTemp.list()) {
      if (entry is File && path.basename(entry.path).endsWith(fileName)) {
        await entry.delete();
      }
    }
    await TestHarness.tearDown();
  });

  Future<void> openImport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => UnifiedMediaImportDialog(
                mediaType: 'audio',
                onMediaImported: imported.add,
              ),
            ),
            child: const Text('Open import'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.link));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),
        'http://${server.address.address}:${server.port}/$fileName');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 20000; i++) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 1),
          ));
      await tester.pump(const Duration(milliseconds: 50));
      if (done()) return;
    }
    fail('The URL import did not reach the expected state');
  }

  Future<void> expectNoOutput(WidgetTester tester) async {
    expect(imported, isEmpty);
    await tester.runAsync(() async {
      expect(
        await TestHarness.applicationDocumentsDirectory
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList(),
        isEmpty,
      );
      expect(
        await Directory.systemTemp
            .list()
            .where((entry) => path.basename(entry.path).endsWith(fileName))
            .toList(),
        isEmpty,
      );
    });
  }

  for (final compressed in [false, true]) {
    testWidgets('imports decoded media (gzip: $compressed)', (tester) async {
      final bytes = List<int>.generate(4096, (index) => index % 256);
      server.listen((request) async {
        final body = compressed ? gzip.encode(bytes) : bytes;
        if (compressed) {
          request.response.headers
              .set(HttpHeaders.contentEncodingHeader, 'gzip');
          request.response.contentLength = body.length;
        }
        // The plain response deliberately uses chunked transfer with no length.
        request.response.add(body);
        await request.response.close();
      });
      await openImport(tester);
      await pumpUntil(tester, () => imported.isNotEmpty);
      await tester.runAsync(() async {
        expect(await File(imported.single).readAsBytes(), bytes);
        expect(
          await Directory.systemTemp
              .list()
              .where((entry) => path.basename(entry.path).endsWith(fileName))
              .toList(),
          isEmpty,
        );
      });
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  }

  testWidgets('accepts decoded media exactly at the 100 MiB limit',
      (tester) async {
    const limit = 100 * 1024 * 1024;
    final body = gzip.encode(Uint8List(limit));
    server.listen((request) async {
      request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.contentLength = body.length;
      request.response.add(body);
      await request.response.close();
    });
    await openImport(tester);
    await pumpUntil(tester, () => imported.isNotEmpty);
    await tester.runAsync(() async {
      expect(await File(imported.single).length(), limit);
    });
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('rejects gzip expansion above 100 MiB before persisting media',
      (tester) async {
    // A tiny wire payload expands past the import budget by a single byte.
    final body = gzip.encode(Uint8List(100 * 1024 * 1024 + 1));
    expect(body.length, lessThan(128 * 1024));
    server.listen((request) async {
      request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.contentLength = body.length;
      request.response.add(body);
      await request.response.close();
    });
    await openImport(tester);
    await pumpUntil(
      tester,
      () =>
          imported.isNotEmpty || find.byIcon(Icons.link).evaluate().isNotEmpty,
    );
    await expectNoOutput(tester);
    expect(find.textContaining('100 MB'), findsOneWidget);
  });

  for (final dispose in [false, true]) {
    testWidgets(
        '${dispose ? 'closing' : 'cancelling'} aborts a stalled download',
        (tester) async {
      var requested = false;
      var disconnected = false;
      server.listen((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        detachedSockets.add(socket);
        socket.listen(
          (_) {},
          onDone: () => disconnected = true,
          onError: (Object _) => disconnected = true,
        );
        if (!dispose) {
          socket.write('HTTP/1.1 200 OK\r\n'
              'Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n');
          await socket.flush();
        }
        requested = true;
        // Leave the response open: Cancel must not require another body chunk.
      });
      await openImport(tester);
      await pumpUntil(
        tester,
        () =>
            requested &&
            (dispose ||
                Directory.systemTemp.listSync().whereType<File>().any(
                      (file) =>
                          path.basename(file.path).endsWith(fileName) &&
                          file.lengthSync() == 3,
                    )),
      );
      if (dispose) {
        await tester.pumpWidget(const SizedBox());
      } else {
        await tester.tap(find.text('Cancel import'));
      }
      await pumpUntil(
        tester,
        () =>
            disconnected &&
            !Directory.systemTemp.listSync().any(
                  (entry) => path.basename(entry.path).endsWith(fileName),
                ),
      );
      await expectNoOutput(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
