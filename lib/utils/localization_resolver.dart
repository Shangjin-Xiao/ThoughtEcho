import 'dart:ui' show Locale, PlatformDispatcher;

import '../gen_l10n/app_localizations.dart';

/// 将语言字符串（如 'zh-Hant'、'zh_TW'、'zh_CN'、'en'）解析为标准 [Locale]。
///
/// 支持 RFC 5646 / BCP 47 与下划线格式，正确识别 4 位字母的 Script 代码（如 'Hant'）
/// 与 2 位字母的 Country 代码（如 'TW'），避免直接使用 `Locale(string)` 时将
/// scriptCode 误置为 countryCode 或 languageCode。
Locale? parseLocale(String? localeCode) {
  if (localeCode == null || localeCode.trim().isEmpty) return null;
  final parts = localeCode.trim().split(RegExp(r'[_-]'));
  if (parts.length == 1) {
    return Locale(parts[0].toLowerCase());
  }
  if (parts.length == 2) {
    if (parts[1].length == 4) {
      final script =
          parts[1][0].toUpperCase() + parts[1].substring(1).toLowerCase();
      return Locale.fromSubtags(
        languageCode: parts[0].toLowerCase(),
        scriptCode: script,
      );
    }
    return Locale(parts[0].toLowerCase(), parts[1].toUpperCase());
  }
  final script = parts[1].length == 4
      ? parts[1][0].toUpperCase() + parts[1].substring(1).toLowerCase()
      : null;
  final country = parts[1].length == 4
      ? (parts.length > 2 ? parts[2].toUpperCase() : null)
      : parts[1].toUpperCase();
  return Locale.fromSubtags(
    languageCode: parts[0].toLowerCase(),
    scriptCode: script,
    countryCode: country,
  );
}

/// 在没有 `BuildContext` 的地方取一份 [AppLocalizations]。
///
/// Service 和 Agent 工具拿不到 context，但它们交给模型的文案（天气、时间段这类
/// 枚举 key）同样要跟着用户的语言走——否则界面显示「多云」，喂给 AI 的却是
/// `partly_cloudy`，模型回信时只能照抄那个英文 key。
///
/// [localeCode] 传 `SettingsService.localeCode`；为空表示跟随系统。
/// 对繁体中文（zh-Hant、zh_TW 等）正确匹配 [AppLocalizationsZhHant]，
/// 不在支持列表里的语言退回英文，和 `MaterialApp` 的 `supportedLocales` 协商结果一致。
AppLocalizations resolveAppLocalizations(String? localeCode) {
  final targetLocale =
      parseLocale(localeCode) ?? PlatformDispatcher.instance.locale;

  if (targetLocale.languageCode.toLowerCase() == 'zh') {
    final script = targetLocale.scriptCode?.toLowerCase();
    final country = targetLocale.countryCode?.toUpperCase();
    if (script == 'hant' ||
        country == 'TW' ||
        country == 'HK' ||
        country == 'MO') {
      return lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    }
    return lookupAppLocalizations(const Locale('zh'));
  }

  final supported = AppLocalizations.supportedLocales
      .map((locale) => locale.languageCode.toLowerCase())
      .toSet();

  final lang = targetLocale.languageCode.toLowerCase();
  return lookupAppLocalizations(
    Locale(supported.contains(lang) ? lang : 'en'),
  );
}
