import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:thoughtecho/services/network_service.dart';
import 'package:thoughtecho/services/pdf_font_service.dart';
import 'package:thoughtecho/theme/theme_style.dart';

import '../../test_harness.dart';

class _TestHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) fetchHandler;

  _TestHttpClientAdapter(this.fetchHandler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return fetchHandler(options);
  }

  @override
  void close({bool force = false}) {}
}

ByteData _buildFontDataWithTables(List<String> tableTags) {
  final data = ByteData(12 + tableTags.length * 16);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, tableTags.length);
  for (var index = 0; index < tableTags.length; index++) {
    final tag = tableTags[index];
    final offset = 12 + index * 16;
    for (var charIndex = 0; charIndex < tag.length; charIndex++) {
      data.setUint8(offset + charIndex, tag.codeUnitAt(charIndex));
    }
  }
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PdfFontService.resetAllCachesForTesting();
    PdfFontService.disableExternalLoadingForTesting = true;
  });

  tearDown(() {
    PdfFontService.resetAllCachesForTesting();
  });

  group('PdfFontService Unit Tests', () {
    test('isValidFontData correctly validates font format magic numbers', () {
      // Standard TTF (0x00010000)
      final ttfData = ByteData(4)..setUint32(0, 0x00010000);
      expect(PdfFontService.isValidFontData(ttfData), isTrue);

      // Apple TTF ('true' / 0x74727565)
      final appleTtfData = ByteData(4)..setUint32(0, 0x74727565);
      expect(PdfFontService.isValidFontData(appleTtfData), isTrue);

      // CFF OTF ('OTTO' / 0x4F54544F) - unsupported for PDF Unicode encoding
      final otfData = ByteData(4)..setUint32(0, 0x4F54544F);
      expect(PdfFontService.isValidFontData(otfData), isFalse);

      // TTC ('ttcf' / 0x74746366) - collection format unsupported
      final ttcData = ByteData(4)..setUint32(0, 0x74746366);
      expect(PdfFontService.isValidFontData(ttcData), isFalse);

      // Too short data (<4 bytes)
      final shortData = ByteData(3);
      expect(PdfFontService.isValidFontData(shortData), isFalse);

      // Arbitrary invalid data
      final invalidData = ByteData(4)..setUint32(0, 0xDEADBEEF);
      expect(PdfFontService.isValidFontData(invalidData), isFalse);
    });

    test('isValidEmojiFontData validates presence of CBDT and CBLC tables', () {
      // Valid bitmap emoji font with CBDT and CBLC tables
      final validEmojiData = _buildFontDataWithTables(['CBDT', 'CBLC']);
      expect(PdfFontService.isValidEmojiFontData(validEmojiData), isTrue);

      // Only CBDT missing CBLC
      final cbdtOnly = _buildFontDataWithTables(['CBDT', 'head']);
      expect(PdfFontService.isValidEmojiFontData(cbdtOnly), isFalse);

      // Vector emoji font (COLR/CPAL)
      final vectorEmojiData = _buildFontDataWithTables(['COLR', 'CPAL']);
      expect(PdfFontService.isValidEmojiFontData(vectorEmojiData), isFalse);

      // Header too short for declared tables length
      final truncatedHeader = ByteData(12)
        ..setUint32(0, 0x00010000)
        ..setUint16(4, 5);
      expect(PdfFontService.isValidEmojiFontData(truncatedHeader), isFalse);
    });

    test(
        'takeValidCachedFontDataForTesting returns cached font or clears invalid cache',
        () {
      // Set valid TTF
      final validTtf = ByteData(4)..setUint32(0, 0x00010000);
      PdfFontService.setCachedFontDataForTesting(validTtf);
      expect(
          PdfFontService.takeValidCachedFontDataForTesting(), equals(validTtf));

      // Set invalid font data
      final invalidOtf = ByteData(4)..setUint32(0, 0x4F54544F);
      PdfFontService.setCachedFontDataForTesting(invalidOtf);
      expect(PdfFontService.takeValidCachedFontDataForTesting(), isNull);
      // Cache should now be cleared to null
      expect(PdfFontService.takeValidCachedFontDataForTesting(), isNull);
    });

    test('loadFontSet with cached font data produces non-fallback PdfFontSet',
        () async {
      final validFontData = ByteData(4)..setUint32(0, 0x00010000);
      PdfFontService.setCachedFontDataForTesting(validFontData);

      final fontSet = await PdfFontService.loadFontSet();
      expect(fontSet.isFallback, isFalse);
      expect(fontSet.regular, isA<pw.Font>());
      expect((fontSet.regular as pw.TtfFont).data, equals(validFontData));
      expect(fontSet.bold, isA<pw.Font>());
      expect(fontSet.italic, isA<pw.Font>());
      expect(fontSet.boldItalic, isA<pw.Font>());
    });

    test(
        'loadFontSet with bundledSerif loads bundled font and includes regular font in fallback list',
        () async {
      final serifFontData = ByteData(4)..setUint32(0, 0x00010000);
      final mainFontData = ByteData(4)..setUint32(0, 0x74727565);

      PdfFontService.setCachedFontDataForTesting(mainFontData);
      PdfFontService.setCachedBundledSerifDataForTesting(serifFontData);

      final fontSet = await PdfFontService.loadFontSet(
          readingFontFamily: ThemeStyleForm.bundledSerif);
      expect(fontSet.isFallback, isFalse);
      expect((fontSet.regular as pw.TtfFont).data, equals(serifFontData));
      expect(fontSet.fallbackFonts, isNotEmpty);
      expect((fontSet.fallbackFonts.first as pw.TtfFont).data,
          equals(mainFontData));
    });

    test('loadFont returns TTF font with cached data when cache is present',
        () async {
      final validTtfData = ByteData(4)..setUint32(0, 0x00010000);
      PdfFontService.setCachedFontDataForTesting(validTtfData);

      final font = await PdfFontService.loadFont();
      expect(font, isA<pw.TtfFont>());
      expect((font as pw.TtfFont).data, equals(validTtfData));
    });

    test('loadFont falls back to Helvetica when no font data is available',
        () async {
      PdfFontService.setCachedFontDataForTesting(null);
      PdfFontService.disableExternalLoadingForTesting = true;

      final font = await PdfFontService.loadFont();
      expect(font, isNot(isA<pw.TtfFont>()));
      expect(font.font, equals(pw.Type1Fonts.helvetica));
    });

    group('PdfFontService Cache Self-Healing Tests', () {
      setUp(() async {
        await TestHarness.initialize();
        PdfFontService.resetAllCachesForTesting();
      });

      tearDown(() async {
        PdfFontService.resetAllCachesForTesting();
        await TestHarness.tearDown();
      });

      test('corrupted font file on disk is detected, deleted, and returns null',
          () async {
        final docDir = await getApplicationDocumentsDirectory();
        final fontFile = File('${docDir.path}/cached_noto_sans_sc.ttf');
        await fontFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF]);
        expect(await fontFile.exists(), isTrue);

        final loaded = await PdfFontService.tryLoadCachedFontForTesting(
          'cached_noto_sans_sc.ttf',
        );

        expect(loaded, isNull);
        expect(await fontFile.exists(), isFalse);
      });

      test(
          'empty 0-byte font file on disk is detected, deleted, and returns null',
          () async {
        final docDir = await getApplicationDocumentsDirectory();
        final fontFile = File('${docDir.path}/cached_noto_sans_sc.ttf');
        await fontFile.writeAsBytes([]);
        expect(await fontFile.exists(), isTrue);

        final loaded = await PdfFontService.tryLoadCachedFontForTesting(
          'cached_noto_sans_sc.ttf',
        );

        expect(loaded, isNull);
        expect(await fontFile.exists(), isFalse);
      });

      test('corrupted emoji font failing custom validator is deleted from disk',
          () async {
        final docDir = await getApplicationDocumentsDirectory();
        final fontFile = File('${docDir.path}/cached_noto_color_emoji.ttf');
        // Valid standard TTF magic, but lacks CBDT/CBLC bitmap emoji tables
        final ttfData = ByteData(4)..setUint32(0, 0x00010000);
        await fontFile.writeAsBytes(ttfData.buffer.asUint8List());
        expect(await fontFile.exists(), isTrue);

        final loaded = await PdfFontService.tryLoadCachedFontForTesting(
          'cached_noto_color_emoji.ttf',
          validator: PdfFontService.isValidEmojiFontData,
        );

        expect(loaded, isNull);
        expect(await fontFile.exists(), isFalse);
      });

      test('valid font file on disk is loaded successfully and preserved',
          () async {
        final docDir = await getApplicationDocumentsDirectory();
        final fontFile = File('${docDir.path}/cached_noto_sans_sc.ttf');
        final ttfData = ByteData(4)..setUint32(0, 0x00010000);
        await fontFile.writeAsBytes(ttfData.buffer.asUint8List());

        final loaded = await PdfFontService.tryLoadCachedFontForTesting(
          'cached_noto_sans_sc.ttf',
        );

        expect(loaded, isNotNull);
        expect(loaded!.lengthInBytes, 4);
        expect(await fontFile.exists(), isTrue);
      });
    });

    group('PdfFontService In-flight Dedup and Atomic Temp Write Tests', () {
      setUp(() async {
        await TestHarness.initialize();
        PdfFontService.resetAllCachesForTesting();
        NetworkService.instanceForTesting = null;
      });

      tearDown(() async {
        PdfFontService.resetAllCachesForTesting();
        NetworkService.instanceForTesting = null;
        await TestHarness.tearDown();
      });

      test(
          'concurrent download requests for the same font deduplicate to 1 HTTP request',
          () async {
        var networkRequestCount = 0;
        final validTtfBytes =
            (ByteData(4)..setUint32(0, 0x00010000)).buffer.asUint8List();

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          networkRequestCount++;
          // Simulate latency to guarantee overlap of concurrent callers
          await Future.delayed(const Duration(milliseconds: 30));
          return ResponseBody.fromBytes(validTtfBytes, 200);
        });

        PdfFontService.dioForTesting = dio;

        // Trigger 10 concurrent calls for the same font file
        final results = await Future.wait(
          List.generate(
            10,
            (_) => PdfFontService.downloadAndCacheFontForTesting(
              fileName: 'cached_test_font.ttf',
              urls: ['https://example.com/font.ttf'],
            ),
          ),
        );

        expect(networkRequestCount, equals(1));
        for (final res in results) {
          expect(res, isNotNull);
          expect(res!.lengthInBytes, 4);
        }
        expect(PdfFontService.inFlightDownloadsCountForTesting, equals(0));

        // Confirm target file exists on disk
        final docDir = await getApplicationDocumentsDirectory();
        final targetFile = File('${docDir.path}/cached_test_font.ttf');
        final tempFile = File('${docDir.path}/cached_test_font.ttf.tmp');
        expect(await targetFile.exists(), isTrue);
        expect(await tempFile.exists(), isFalse);
      });

      test(
          'successful download writes to .tmp first and atomically replaces target file',
          () async {
        final validTtfBytes =
            (ByteData(4)..setUint32(0, 0x00010000)).buffer.asUint8List();

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          return ResponseBody.fromBytes(validTtfBytes, 200);
        });
        PdfFontService.dioForTesting = dio;

        final result = await PdfFontService.downloadAndCacheFontForTesting(
          fileName: 'atomic_test_font.ttf',
          urls: ['https://example.com/font.ttf'],
        );

        expect(result, isNotNull);
        final docDir = await getApplicationDocumentsDirectory();
        final targetFile = File('${docDir.path}/atomic_test_font.ttf');
        final tempFile = File('${docDir.path}/atomic_test_font.ttf.tmp');

        expect(await targetFile.exists(), isTrue);
        expect(await tempFile.exists(), isFalse);
        expect(await targetFile.readAsBytes(), equals(validTtfBytes));
      });

      test(
          'invalid font data deletes .tmp file and does not create target file',
          () async {
        final invalidBytes = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          return ResponseBody.fromBytes(invalidBytes, 200);
        });
        PdfFontService.dioForTesting = dio;

        final result = await PdfFontService.downloadAndCacheFontForTesting(
          fileName: 'invalid_test_font.ttf',
          urls: ['https://example.com/font.ttf'],
        );

        expect(result, isNull);
        final docDir = await getApplicationDocumentsDirectory();
        final targetFile = File('${docDir.path}/invalid_test_font.ttf');
        final tempFile = File('${docDir.path}/invalid_test_font.ttf.tmp');

        expect(await targetFile.exists(), isFalse);
        expect(await tempFile.exists(), isFalse);
      });

      test('network exception cleans up .tmp file safely', () async {
        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'Simulated connection failure',
          );
        });
        PdfFontService.dioForTesting = dio;

        final result = await PdfFontService.downloadAndCacheFontForTesting(
          fileName: 'failed_test_font.ttf',
          urls: ['https://example.com/font.ttf'],
        );

        expect(result, isNull);
        final docDir = await getApplicationDocumentsDirectory();
        final targetFile = File('${docDir.path}/failed_test_font.ttf');
        final tempFile = File('${docDir.path}/failed_test_font.ttf.tmp');

        expect(await targetFile.exists(), isFalse);
        expect(await tempFile.exists(), isFalse);
      });

      test(
          'reuses NetworkService.instance.generalDio when dioForTesting is null',
          () async {
        final validTtfBytes =
            (ByteData(4)..setUint32(0, 0x00010000)).buffer.asUint8List();

        final networkService = NetworkService.instance;
        await networkService.init();

        var generalDioCalled = false;
        networkService.generalDioForTesting.httpClientAdapter =
            _TestHttpClientAdapter((options) async {
          generalDioCalled = true;
          return ResponseBody.fromBytes(validTtfBytes, 200);
        });

        // Ensure dioForTesting is null so it falls back to NetworkService.instance.generalDio
        PdfFontService.dioForTesting = null;

        final result = await PdfFontService.downloadAndCacheFontForTesting(
          fileName: 'network_service_dio_test.ttf',
          urls: ['https://example.com/font.ttf'],
        );

        expect(result, isNotNull);
        expect(generalDioCalled, isTrue);
      });

      test(
          'concurrent loadFontSet calls deduplicate downloads for the same font file',
          () async {
        final requestCounts = <String, int>{};
        final validTtfBytes =
            (ByteData(4)..setUint32(0, 0x00010000)).buffer.asUint8List();
        final validEmojiBytes =
            _buildFontDataWithTables(['CBDT', 'CBLC']).buffer.asUint8List();

        final dio = Dio();
        dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
          final url = options.uri.toString();
          requestCounts[url] = (requestCounts[url] ?? 0) + 1;
          await Future.delayed(const Duration(milliseconds: 30));
          if (url.contains('NotoColorEmoji')) {
            return ResponseBody.fromBytes(validEmojiBytes, 200);
          }
          return ResponseBody.fromBytes(validTtfBytes, 200);
        });
        PdfFontService.dioForTesting = dio;
        PdfFontService.disableExternalLoadingForTesting = false;

        final results = await Future.wait(
          List.generate(10, (_) => PdfFontService.loadFontSet()),
        );

        expect(results.length, equals(10));
        for (final set in results) {
          expect(set.isFallback, isFalse);
        }

        // Each unique font URL should only be requested once across all 10 concurrent loadFontSet calls
        for (final count in requestCounts.values) {
          expect(count, equals(1));
        }
      });
    });
  });
}
