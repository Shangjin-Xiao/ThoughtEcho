import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// 文本选择菜单里的「摘录到心迹」入口。
///
/// **只有 Android 有这个能力**：channel 的另一端是
/// `android/app/src/main/kotlin/com/shangjin/thoughtecho/MainActivity.kt`，
/// iOS 的 `AppDelegate.swift` 和 Windows 都没有注册它。
///
/// 原来不判平台，于是 iOS 上每次进主页都会撞一次
/// `MissingPluginException` 并按 ERROR 记进日志 —— 2026-08-28 的 iPad 日志里
/// 一条 trace 就带了 6 条。功能上没坏（异常被接住、返回 null），但它会污染日志、
/// 也会作为错误事件上报到 Sentry，把真问题埋掉。
class ExcerptIntentService {
  static const MethodChannel _channel = MethodChannel(
    'com.shangjin.thoughtecho/excerpt_intent',
  );

  /// [supported] 只给测试用：不传就按真实平台判断。做成注入而不是静态开关，
  /// 是为了让「支持」和「不支持」两条分支都能被覆盖，又不引入可变全局状态。
  const ExcerptIntentService({bool? supported}) : _supported = supported;

  final bool? _supported;

  /// 当前平台有没有这个 channel。
  bool get isSupported => _supported ?? (!kIsWeb && Platform.isAndroid);

  Future<String?> consumePendingExcerptText() async {
    if (!isSupported) return null;
    try {
      final text = await _channel.invokeMethod<String>(
        'consumePendingExcerptText',
      );
      final trimmed = text?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return null;
      }
      return trimmed;
    } on MissingPluginException catch (e) {
      // 平台判断之后还撞上，说明是 Android 侧注册时机出了问题（例如引擎重建）。
      // 仍然要看得见，但它不是「错误」，别再进 Sentry 的错误流。
      logDebug(
        'ExcerptIntentService.consumePendingExcerptText 未找到原生实现: $e',
        source: 'ExcerptIntentService',
      );
      return null;
    } catch (e, stackTrace) {
      logError(
        'ExcerptIntentService.consumePendingExcerptText',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> syncEntryPointEnabled(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setExcerptEntryEnabled', enabled);
    } on MissingPluginException catch (e) {
      logDebug(
        'ExcerptIntentService.syncEntryPointEnabled 未找到原生实现: $e',
        source: 'ExcerptIntentService',
      );
    } catch (e, stackTrace) {
      logError(
        'ExcerptIntentService.syncEntryPointEnabled',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
