import 'package:path/path.dart' as p;

import 'app_logger.dart';
import 'path_security_utils.dart';

/// 富文本 Delta 中媒体路径的解析与重定基。
///
/// 笔记的 Delta 里保存的是媒体文件的**绝对路径**，而应用文档目录在不同设备、
/// 甚至同一台设备的不同安装之间并不一致：
///
/// - Android：`/data/user/0/<包名>/app_flutter`，只与包名有关，重装后不变，
///   所有设备上完全相同；
/// - iOS：`/var/mobile/Containers/Data/Application/<容器UUID>/Documents`，
///   容器 UUID 每次重装/从备份恢复都会变化，跨设备更是完全不同；
/// - Windows：与用户名、安装位置有关。
///
/// 因此从其它设备（或旧容器）合并进来的笔记，其媒体绝对路径在本机是失效的：
/// 图片渲染不出来，媒体引用表也匹配不上，WebDAV 同步据此判断"云端附件无人引用"
/// 而永远不下载。本工具负责把这类路径重新指向**本机**的 `media/` 目录。
class MediaPathResolver {
  const MediaPathResolver._();

  /// 永久媒体目录下允许的子目录。与 `MediaFileService` 的落盘目录保持一致
  /// （`html` 只用于临时目录，不会出现在笔记 Delta 中）。
  static const Set<String> mediaSubFolders = {'images', 'videos', 'audios'};

  static const String _mediaFolder = 'media';

  /// 从任意来源的媒体路径中提取 `media/<子目录>/<文件名>` 形式的尾段。
  ///
  /// 同时接受正斜杠与反斜杠，因此 Windows 导出的
  /// `C:\Users\x\Documents\media\images\a.jpg` 与 iOS 的
  /// `/var/mobile/.../Documents/media/images/a.jpg` 都能解析出
  /// `media/images/a.jpg`。无法识别时返回 `null`（调用方应保持原路径不变）。
  static String? mediaRelativeTail(String rawPath) {
    if (rawPath.isEmpty) return null;

    final unified = rawPath.trim().replaceAll('\\', '/');
    final segments = unified
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList();

    // 从后往前找，命中最靠近文件名的那一组 media/<子目录>，避免用户目录里
    // 恰好也叫 media 的上层目录造成误截。
    for (var i = segments.length - 3; i >= 0; i--) {
      if (segments[i] != _mediaFolder) continue;
      if (!mediaSubFolders.contains(segments[i + 1])) continue;

      final tail = segments.sublist(i);
      if (tail.contains('..')) return null;
      return tail.join('/');
    }

    return null;
  }

  /// 把笔记中记录的媒体路径解析为**本机**可用的绝对路径。
  ///
  /// [appPath] 为当前应用文档目录。以下几种输入都会被归一到本机路径：
  /// 相对路径（备份包格式）、指向其它设备/旧容器的绝对路径、跨平台分隔符路径。
  /// 已经位于本机文档目录下的路径按原样返回；无法识别的路径**保持不变**，
  /// 绝不猜测拼接。
  static String resolveToLocal(String rawPath, String appPath) {
    try {
      if (rawPath.trim().isEmpty) return rawPath;

      var sanitized = rawPath.trim();
      if (sanitized.startsWith('file://')) {
        final uri = Uri.tryParse(sanitized);
        if (uri != null && uri.scheme == 'file') {
          sanitized = uri.toFilePath();
        }
      }

      final normalizedAppPath = p.normalize(appPath);

      // 已经是本机路径：无需改写。
      if (p.isAbsolute(sanitized)) {
        final normalized = p.normalize(sanitized);
        if (normalized == normalizedAppPath ||
            p.isWithin(normalizedAppPath, normalized)) {
          return normalized;
        }
      }

      final tail = mediaRelativeTail(sanitized);
      if (tail == null) {
        // 不是可识别的媒体路径（可能是历史遗留的外部文件引用），保持原样。
        return rawPath;
      }

      final rebased = p.join(
        normalizedAppPath,
        tail.replaceAll('/', p.separator),
      );

      // 路径穿越防护：重定基后的路径必须仍落在文档目录内。
      PathSecurityUtils.validateExtractionPath(rebased, normalizedAppPath);
      return p.normalize(rebased);
    } catch (e) {
      logDebug('媒体路径重定基失败，保持原路径: $rawPath ($e)');
      return rawPath;
    }
  }

  /// 递归重写 Delta JSON 中的媒体路径，使其指向本机文档目录。
  ///
  /// 覆盖 `insert.image`、`insert.video` 与 `insert.custom.audio` 三种嵌入，
  /// 与备份/还原链路处理的嵌入类型保持一致。
  static DeltaRebaseResult rebaseDelta(dynamic deltaJson, String appPath) {
    var changed = false;

    String rewrite(String original) {
      final resolved = resolveToLocal(original, appPath);
      if (resolved != original) changed = true;
      return resolved;
    }

    dynamic walk(dynamic node) {
      if (node is Map) {
        final result = <String, dynamic>{};
        for (final entry in node.entries) {
          final key = entry.key.toString();
          final value = entry.value;

          if (key == 'insert' && value is Map) {
            result[key] = _rewriteInsert(value, rewrite);
          } else {
            result[key] = walk(value);
          }
        }
        return result;
      }

      if (node is List) {
        return node.map(walk).toList();
      }

      return node;
    }

    final rebased = walk(deltaJson);
    return DeltaRebaseResult(delta: rebased, changed: changed);
  }

  static Map<String, dynamic> _rewriteInsert(
    Map<dynamic, dynamic> insert,
    String Function(String original) rewrite,
  ) {
    final result = Map<String, dynamic>.from(insert);

    for (final key in const ['image', 'video']) {
      final value = result[key];
      if (value is String) {
        result[key] = rewrite(value);
      }
    }

    final custom = result['custom'];
    if (custom is Map) {
      final rewrittenCustom = Map<String, dynamic>.from(custom);
      final audio = rewrittenCustom['audio'];
      if (audio is String) {
        rewrittenCustom['audio'] = rewrite(audio);
      }
      result['custom'] = rewrittenCustom;
    }

    return result;
  }
}

/// [MediaPathResolver.rebaseDelta] 的结果：改写后的 Delta 及是否真的发生了改写。
class DeltaRebaseResult {
  const DeltaRebaseResult({required this.delta, required this.changed});

  final dynamic delta;

  /// 为 false 时调用方应跳过写回，避免无谓的数据库更新。
  final bool changed;
}
