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

/// 解析中文 Locale 变体：区分简体（zh）与繁体（zh-Hant）。
///
/// 判定规则：
/// 1. 显式 script 为 'hant' -> `zh-Hant`
/// 2. 显式 script 为 'hans' -> `zh`（即使 country 为 TW/HK/MO 也不覆盖，避免 zh-Hans-TW 误判）
/// 3. 未显式声明 script 时，若 country 为 TW/HK/MO 则推断为繁体 `zh-Hant`，其余为简体 `zh`。
Locale resolveZhLocale(Locale locale) {
  final script = locale.scriptCode?.toLowerCase();
  if (script == 'hant') {
    return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  }
  if (script == 'hans') {
    return const Locale('zh');
  }
  final country = locale.countryCode?.toUpperCase();
  if (country == 'TW' || country == 'HK' || country == 'MO') {
    return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  }
  return const Locale('zh');
}

Locale? _matchCandidate(Locale candidate, Iterable<Locale> supported) {
  if (candidate.languageCode.toLowerCase() == 'zh') {
    return resolveZhLocale(candidate);
  }
  for (final s in supported) {
    if (s.languageCode.toLowerCase() == candidate.languageCode.toLowerCase() &&
        (s.scriptCode == null ||
            s.scriptCode?.toLowerCase() ==
                candidate.scriptCode?.toLowerCase())) {
      return s;
    }
  }
  return null;
}

/// 统一计算实际生效的 Locale（供 MaterialApp 与主题构建共享）。
///
/// 判定顺序：
/// 1. 若 [preferredLocale]（如用户在设置中选择的语言）非空：匹配支持的语言并返回；若不支持则回退至英文 'en'；
/// 2. 若为空：遍历系统偏好列表 [systemLocales]（若为空则回退到系统当前首选 locale）：
///    - 若在 [supportedLocales] 中匹配到对应语言代码（及 script），返回匹配项；
/// 3. 若遍历后均无支持项，最终回退至英文 'en'。
Locale resolveEffectiveLocale({
  Locale? preferredLocale,
  List<Locale>? systemLocales,
  Iterable<Locale>? supportedLocales,
}) {
  final supported = supportedLocales ?? AppLocalizations.supportedLocales;

  if (preferredLocale != null) {
    return _matchCandidate(preferredLocale, supported) ?? const Locale('en');
  }

  final candidates = (systemLocales != null && systemLocales.isNotEmpty)
      ? systemLocales
      : [PlatformDispatcher.instance.locale];

  for (final candidate in candidates) {
    final match = _matchCandidate(candidate, supported);
    if (match != null) return match;
  }

  return const Locale('en');
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
  final targetLocale = resolveEffectiveLocale(
    preferredLocale: parseLocale(localeCode),
  );
  return lookupAppLocalizations(targetLocale);
}
