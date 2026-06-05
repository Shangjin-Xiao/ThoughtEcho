import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

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

  const PdfFontSet({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });
}

class PdfFontService {
  static ByteData? _cachedFontData;

  /// 加载字体数据集合，所有变体均指向同一份中文 TTF 数据
  /// 这可确保 pdf 包在渲染粗体/斜体文字时不会 fallback 到不含 CJK 的内置字体
  static Future<PdfFontSet> loadFontSet() async {
    final data = await _loadFontData();
    if (data != null) {
      // 同一份数据创建四份独立 pw.Font 实例（pdf 包要求每种变体是独立对象）
      // 这样即便字体本身不含真正粗体/斜体，中文也不会乱码
      return PdfFontSet(
        regular: pw.Font.ttf(data),
        bold: pw.Font.ttf(data),
        italic: pw.Font.ttf(data),
        boldItalic: pw.Font.ttf(data),
      );
    }
    // 兜底回退，避免应用崩溃（Helvetica 不含 CJK，仅作最后保底）
    return PdfFontSet(
      regular: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
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
      // 1. 尝试检索 Windows/Android 本地系统自带的中文字体（无网络/极速加载）
      final systemFontData = await _tryLoadLocalSystemFont();
      if (systemFontData != null && isValidFontData(systemFontData)) {
        _cachedFontData = systemFontData;
        logDebug("成功从系统本地路径加载中文字体", source: "PdfFontService");
        return _cachedFontData!;
      }

      // 2. 尝试从应用文档目录中读取已下载并缓存的字体
      final cachedFontData = await _tryLoadCachedFont();
      if (cachedFontData != null && isValidFontData(cachedFontData)) {
        _cachedFontData = cachedFontData;
        logDebug("成功从应用缓存路径加载中文字体", source: "PdfFontService");
        return _cachedFontData!;
      }

      // 3. 动态下载中文字体并写入缓存
      final downloadedFontData = await _downloadAndCacheFont();
      if (downloadedFontData != null && isValidFontData(downloadedFontData)) {
        _cachedFontData = downloadedFontData;
        logDebug("成功动态下载并加载中文字体", source: "PdfFontService");
        return _cachedFontData!;
      }
    } catch (e, stack) {
      logError("_loadFontData 失败，将回退到 PDF 默认系统英文字体",
          error: e, stackTrace: stack);
    }
    return null;
  }

  /// 校验字体数据是否为合法的 TrueType 或 OpenType 格式，排除 TTC 或损坏文件
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
    // TrueType (0x00010000)、OpenType ('OTTO') 或 Apple TrueType ('true')
    final isTtf = bytes[0] == 0x00 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x00 &&
        bytes[3] == 0x00;
    final isOtf = bytes[0] == 0x4F &&
        bytes[1] == 0x54 &&
        bytes[2] == 0x54 &&
        bytes[3] == 0x4F;
    final isAppleTtf = bytes[0] == 0x74 &&
        bytes[1] == 0x72 &&
        bytes[2] == 0x75 &&
        bytes[3] == 0x65;
    return isTtf || isOtf || isAppleTtf;
  }

  /// 检索 Windows/Android 本地中文字体
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
          // 优先使用 TTF 格式（pdf 包兼容更好）
          "/system/fonts/DroidSansFallback.ttf",
          "/system/fonts/DroidSansFallbackFull.ttf",
          // MIUI / 小米定制系统
          "/system/fonts/MiLanProVF.ttf",
          // 华为 EMUI
          "/system/fonts/HWKangXi.ttf",
          "/system/fonts/hwKangXi.ttf",
          // 其他品牌常见路径
          "/system/fonts/NotoSansCJK-Regular.ttc",
          // OTF 格式（部分 AOSP 设备）
          "/system/fonts/NotoSansSC-Regular.otf",
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
  static Future<ByteData?> _tryLoadCachedFont() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final fontFile = File("${docDir.path}/cached_chinese_font.ttf");
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

  /// 从公共 CDN 动态下载小巧精美且支持中文的 TrueType 字体（站酷小薇，约 2.0MB）
  static Future<ByteData?> _downloadAndCacheFont() async {
    final url =
        "https://fonts.gstatic.com/s/zcoolxiaowei/v13/q5uD35KLXuK6LALR-3uPA4vS0D2d2tL5.ttf";
    try {
      logDebug("开始网络下载中文字体: $url", source: "PdfFontService");
      final dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null && response.data!.isNotEmpty) {
        final bytes = Uint8List.fromList(response.data!);
        final docDir = await getApplicationDocumentsDirectory();
        final fontFile = File("${docDir.path}/cached_chinese_font.ttf");
        await fontFile.writeAsBytes(bytes);
        logDebug("中文字体下载成功，并已缓存至: ${fontFile.path}", source: "PdfFontService");
        return ByteData.view(bytes.buffer);
      }
    } catch (e) {
      logDebug("网络下载字体失败: $e", source: "PdfFontService");
    }
    return null;
  }
}
