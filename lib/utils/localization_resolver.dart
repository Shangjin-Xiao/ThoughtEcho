import 'dart:ui' show Locale, PlatformDispatcher;

import '../gen_l10n/app_localizations.dart';

/// 在没有 `BuildContext` 的地方取一份 [AppLocalizations]。
///
/// Service 和 Agent 工具拿不到 context，但它们交给模型的文案（天气、时间段这类
/// 枚举 key）同样要跟着用户的语言走——否则界面显示「多云」，喂给 AI 的却是
/// `partly_cloudy`，模型回信时只能照抄那个英文 key。
///
/// [localeCode] 传 `SettingsService.localeCode`；为空表示跟随系统。不在支持列表里
/// 的语言退回英文，和 `MaterialApp` 的 `supportedLocales` 协商结果一致。
AppLocalizations resolveAppLocalizations(String? localeCode) {
  final preferred = localeCode == null || localeCode.isEmpty
      ? PlatformDispatcher.instance.locale
      : Locale(localeCode);

  final supported = AppLocalizations.supportedLocales
      .map((locale) => locale.languageCode)
      .toSet();

  return lookupAppLocalizations(
    supported.contains(preferred.languageCode) ? preferred : const Locale('en'),
  );
}
