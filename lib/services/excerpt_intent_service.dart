import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

class ExcerptIntentService {
  static const MethodChannel _channel = MethodChannel(
    'com.shangjin.thoughtecho/excerpt_intent',
  );

  const ExcerptIntentService();

  Future<String?> consumePendingExcerptText() async {
    try {
      final text = await _channel.invokeMethod<String>(
        'consumePendingExcerptText',
      );
      final trimmed = text?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return null;
      }
      return trimmed;
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
    try {
      await _channel.invokeMethod<void>('setExcerptEntryEnabled', enabled);
    } catch (e, stackTrace) {
      logError(
        'ExcerptIntentService.syncEntryPointEnabled',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
