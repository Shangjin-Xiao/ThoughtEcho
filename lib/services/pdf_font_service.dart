import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class PdfFontService {
  static pw.Font? _cachedFont;

  /// 加载最合适的中文字体，检索本地或动态下载缓存，保障 PDF 正确呈现中文字符
  static Future<pw.Font> loadFont() async {
    if (_cachedFont != null) {
      return _cachedFont!;
    }

    try {
      // 1. 尝试检索 Windows/Android 本地系统自带的中文字体（无网络/极速加载）
      final systemFontData = await _tryLoadLocalSystemFont();
      if (systemFontData != null) {
        _cachedFont = pw.Font.ttf(systemFontData);
        logDebug("成功从系统本地路径加载中文字体", source: "PdfFontService");
        return _cachedFont!;
      }

      // 2. 尝试从应用文档目录中读取已下载并缓存的字体
      final cachedFontData = await _tryLoadCachedFont();
      if (cachedFontData != null) {
        _cachedFont = pw.Font.ttf(cachedFontData);
        logDebug("成功从应用缓存路径加载中文字体", source: "PdfFontService");
        return _cachedFont!;
      }

      // 3. 动态下载中文字体并写入缓存
      final downloadedFontData = await _downloadAndCacheFont();
      if (downloadedFontData != null) {
        _cachedFont = pw.Font.ttf(downloadedFontData);
        logDebug("成功动态下载并加载中文字体", source: "PdfFontService");
        return _cachedFont!;
      }
    } catch (e, stack) {
      logError("loadFont 失败，将回退到 PDF 默认系统英文字体", error: e, stackTrace: stack);
    }

    // 4. 兜底回退，避免应用崩溃
    return pw.Font.helvetica();
  }

  /// 检索 Windows/Android 本地中文字体
  static Future<ByteData?> _tryLoadLocalSystemFont() async {
    try {
      if (Platform.isWindows) {
        final paths = [
          "C:\\Windows\\Fonts\\msyh.ttc",
          "C:\\Windows\\Fonts\\msyh.ttf",
          "C:\\Windows\\Fonts\\simsun.ttc",
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
          "/system/fonts/NotoSansSC-Regular.otf",
          "/system/fonts/DroidSansFallback.ttf",
          "/system/fonts/NotoSansCJK-Regular.ttc",
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
