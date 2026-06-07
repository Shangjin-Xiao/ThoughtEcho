import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:thoughtecho/utils/app_logger.dart';

/// 字体数据集合，包含用于创建粗体/斜体/粗斜体变体所需的相同 TTF 数据
class PdfFontSet {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;
  final List<pw.Font> fallbackFonts;
  final bool isFallback;

  const PdfFontSet({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    this.fallbackFonts = const [],
    this.isFallback = false,
  });
}

class PdfFontService {
  static ByteData? _cachedFontData;
  static final Map<String, ByteData> _cachedLanguageFallbackData = {};
  static ByteData? _cachedEmojiFontData;

  static const _multilingualFontFileName = "cached_noto_sans_sc.ttf";
  static const _obsoleteMultilingualFontFileName =
      "cached_noto_sans_cjk_sc.otf";
  static const _japaneseFontFileName = "cached_noto_sans_jp.ttf";
  static const _koreanFontFileName = "cached_noto_sans_kr.ttf";
  static const _emojiFontFileName = "cached_noto_color_emoji.ttf";

  static const _multilingualFontUrls = [
    "https://fonts.gstatic.com/s/notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYxNbPzS5HE.ttf",
  ];

  static const _languageFallbackFonts = [
    (
      fileName: _japaneseFontFileName,
      urls: [
        "https://fonts.gstatic.com/s/notosansjp/v53/-F6jfjtqLzI2JPCgQBnw7HFyzSD-AsregP8VFBEj75vY0rw-oME.ttf",
      ],
    ),
    (
      fileName: _koreanFontFileName,
      urls: [
        "https://fonts.gstatic.com/s/notosanskr/v36/PbyxFmXiEBPT4ITbgNA5Cgms3VYcOA-vvnIzzuoyeLTq8H4hfeE.ttf",
      ],
    ),
  ];

  static const _emojiFontUrls = [
    "https://fonts.gstatic.com/s/notocoloremoji/v30/Yq6P-KqIXTD0t4D9z1ESnKM3-HpFab5s79iz64w.ttf",
    "https://rawcdn.githack.com/googlefonts/noto-emoji/9a5261d871451f9b5183c93483cbd68ed916b1e9/fonts/NotoColorEmoji.ttf",
  ];

  /// 加载字体数据集合，所有变体均指向同一份中文 TTF 数据
  /// 这可确保 pdf 包在渲染粗体/斜体文字时不会 fallback 到不含 CJK 的内置字体
  static Future<PdfFontSet> loadFontSet() async {
    final data = await _loadFontData();
    final languageFallbackData = await _loadLanguageFallbackFontData();
    final emojiData = await _loadEmojiFontData();
    final fallbackFonts = <pw.Font>[
      ...languageFallbackData.map(pw.Font.ttf),
      if (emojiData != null) pw.Font.ttf(emojiData),
    ];
    if (data != null) {
      // 同一份数据创建四份独立 pw.Font 实例（pdf 包要求每种变体是独立对象）
      // 这样即便字体本身不含真正粗体/斜体，中文也不会乱码
      return PdfFontSet(
        regular: pw.Font.ttf(data),
        bold: pw.Font.ttf(data),
        italic: pw.Font.ttf(data),
        boldItalic: pw.Font.ttf(data),
        fallbackFonts: fallbackFonts,
        isFallback: false,
      );
    }
    // 兜底回退，避免应用崩溃（Helvetica 不含 CJK，仅作最后保底）
    return PdfFontSet(
      regular: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
      fallbackFonts: fallbackFonts,
      isFallback: true,
    );
  }

  /// 仅加载 regular 字体，向后兼容接口（优先使用 loadFontSet）
  static Future<pw.Font> loadFont() async {
    final data = await _loadFontData();
    if (data != null) {
      return pw.Font.ttf(data);
    }
    return pw.Font.helvetica();
  }

  static Future<ByteData?> _loadFontData() async {
    if (_cachedFontData != null) {
      return _cachedFontData!;
    }
    try {
      await _removeObsoleteFontCache();

      // 1. 优先读取覆盖中日韩及拉丁字符的已缓存 Noto Sans CJK。
      final cachedFontData =
          await _tryLoadCachedFont(_multilingualFontFileName);
      if (cachedFontData != null && isValidFontData(cachedFontData)) {
        _cachedFontData = cachedFontData;
        logDebug("成功从应用缓存路径加载多语言字体", source: "PdfFontService");
        return _cachedFontData!;
      }

      // 2. 下载并缓存标准 Noto Sans CJK，确保中日韩字形稳定一致。
      final downloadedFontData = await _downloadAndCacheFont(
        fileName: _multilingualFontFileName,
        urls: _multilingualFontUrls,
      );
      if (downloadedFontData != null && isValidFontData(downloadedFontData)) {
        _cachedFontData = downloadedFontData;
        logDebug("成功动态下载并加载多语言字体", source: "PdfFontService");
        return _cachedFontData!;
      }

      // 3. 网络不可用时尝试系统字体作为降级。
      final systemFontData = await _tryLoadLocalSystemFont();
      if (systemFontData != null && isValidFontData(systemFontData)) {
        _cachedFontData = systemFontData;
        logDebug("成功从系统本地路径加载多语言字体", source: "PdfFontService");
        return _cachedFontData!;
      }
    } catch (e, stack) {
      logError("_loadFontData 失败，将回退到 PDF 默认系统英文字体",
          error: e, stackTrace: stack);
    }
    return null;
  }

  static Future<ByteData?> _loadEmojiFontData() async {
    if (_cachedEmojiFontData != null) {
      return _cachedEmojiFontData!;
    }
    final cached = await _tryLoadCachedFont(_emojiFontFileName);
    if (cached != null && isValidFontData(cached)) {
      _cachedEmojiFontData = cached;
      return cached;
    }
    final downloaded = await _downloadAndCacheFont(
      fileName: _emojiFontFileName,
      urls: _emojiFontUrls,
    );
    if (downloaded != null && isValidFontData(downloaded)) {
      _cachedEmojiFontData = downloaded;
      return downloaded;
    }
    return null;
  }

  static Future<List<ByteData>> _loadLanguageFallbackFontData() async {
    for (final config in _languageFallbackFonts) {
      if (_cachedLanguageFallbackData.containsKey(config.fileName)) {
        continue;
      }
      final cached = await _tryLoadCachedFont(config.fileName);
      if (cached != null && isValidFontData(cached)) {
        _cachedLanguageFallbackData[config.fileName] = cached;
        continue;
      }
      final downloaded = await _downloadAndCacheFont(
        fileName: config.fileName,
        urls: config.urls,
      );
      if (downloaded != null && isValidFontData(downloaded)) {
        _cachedLanguageFallbackData[config.fileName] = downloaded;
      }
    }
    return List.unmodifiable(_cachedLanguageFallbackData.values);
  }

  /// 仅接受 pdf 包可稳定进行 Unicode 子集编码的 TrueType 字体。
  @visibleForTesting
  static bool isValidFontData(ByteData data) {
    if (data.lengthInBytes < 4) return false;
    final bytes = data.buffer.asUint8List(data.offsetInBytes, 4);
    // 排除 TrueType Collection (TTC) 格式，其魔术字为 'ttcf' (0x74746366)
    if (bytes[0] == 0x74 &&
        bytes[1] == 0x74 &&
        bytes[2] == 0x63 &&
        bytes[3] == 0x66) {
      return false;
    }
    // CFF OpenType ('OTTO') 会在 pdf 包排版 Unicode 时回退到 Latin-1。
    final isTtf = bytes[0] == 0x00 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x00 &&
        bytes[3] == 0x00;
    final isAppleTtf = bytes[0] == 0x74 &&
        bytes[1] == 0x72 &&
        bytes[2] == 0x75 &&
        bytes[3] == 0x65;
    return isTtf || isAppleTtf;
  }

  /// 检索 Windows/Android/Linux 本地中文字体
  static Future<ByteData?> _tryLoadLocalSystemFont() async {
    try {
      if (Platform.isWindows) {
        final paths = [
          "C:\\Windows\\Fonts\\simhei.ttf",
          "C:\\Windows\\Fonts\\deng.ttf",
          "C:\\Windows\\Fonts\\msyh.ttf",
          "C:\\Windows\\Fonts\\simsun.ttf",
        ];
        for (final p in paths) {
          final f = File(p);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            if (bytes.isNotEmpty) {
              return ByteData.view(bytes.buffer);
            }
          }
        }
      } else if (Platform.isAndroid) {
        final paths = [
          // 优先使用 TTF/OTF 格式（pdf 包兼容更好，排除了不支持的 TTC 格式）
          "/system/fonts/NotoSansSC-Regular.otf",
          "/system/fonts/NotoSansSC-Regular.ttf",
          "/system/fonts/SourceHanSansCN-Regular.otf",
          "/system/fonts/SourceHanSans-Regular.ttf",
          "/system/fonts/SourceHanSansSC-Regular.otf",
          "/system/fonts/SourceHanSansTC-Regular.otf",
          "/system/fonts/NotoSansCJKsc-Regular.otf",
          "/system/fonts/NotoSansCJKtc-Regular.otf",
          "/system/fonts/NotoSansCJK-Regular.otf",
          "/system/fonts/DroidSansFallback.ttf",
          "/system/fonts/DroidSansFallbackFull.ttf",
          // MIUI / 小米定制系统
          "/system/fonts/MiLanProVF.ttf",
          // 华为 EMUI
          "/system/fonts/HWKangXi.ttf",
          "/system/fonts/hwKangXi.ttf",
        ];
        for (final p in paths) {
          final f = File(p);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            if (bytes.isNotEmpty) {
              return ByteData.view(bytes.buffer);
            }
          }
        }
      } else if (Platform.isLinux) {
        final paths = [
          "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
          "/usr/share/fonts/truetype/droid/DroidSansFallback.ttf",
          "/usr/share/fonts/truetype/wqy/wqy-microhei.ttf",
          "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttf",
        ];
        for (final p in paths) {
          final f = File(p);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            if (bytes.isNotEmpty) {
              return ByteData.view(bytes.buffer);
            }
          }
        }
      }
    } catch (e) {
      logDebug("本地系统中文字体检索异常: $e", source: "PdfFontService");
    }
    return null;
  }

  /// 读取已下载缓存的字体
  static Future<ByteData?> _tryLoadCachedFont(String fileName) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final fontFile = File("${docDir.path}/$fileName");
      if (await fontFile.exists()) {
        final bytes = await fontFile.readAsBytes();
        if (bytes.isNotEmpty) {
          return ByteData.view(bytes.buffer);
        }
      }
    } catch (e) {
      logDebug("读取本地缓存字体异常: $e", source: "PdfFontService");
    }
    return null;
  }

  static Future<void> _removeObsoleteFontCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final oldFont = File("${docDir.path}/$_obsoleteMultilingualFontFileName");
      if (await oldFont.exists()) {
        await oldFont.delete();
      }
    } catch (e) {
      logDebug("清理旧版 PDF 字体缓存异常: $e", source: "PdfFontService");
    }
  }

  static Future<ByteData?> _downloadAndCacheFont({
    required String fileName,
    required List<String> urls,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ));

    for (final url in urls) {
      try {
        logDebug("开始网络下载 PDF 字体: $url", source: "PdfFontService");
        final response = await dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.data != null && response.data!.isNotEmpty) {
          final bytes = Uint8List.fromList(response.data!);
          final byteData = ByteData.view(bytes.buffer);
          if (isValidFontData(byteData)) {
            final docDir = await getApplicationDocumentsDirectory();
            final fontFile = File("${docDir.path}/$fileName");
            await fontFile.writeAsBytes(bytes);
            logDebug("PDF 字体下载成功，并已缓存至: ${fontFile.path}",
                source: "PdfFontService");
            return byteData;
          } else {
            logDebug("下载的字体数据格式无效，跳过该源: $url", source: "PdfFontService");
          }
        }
      } catch (e) {
        logDebug("从 $url 下载中文字体失败: $e", source: "PdfFontService");
      }
    }
    return null;
  }
}
