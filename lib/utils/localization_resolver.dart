import 'dart:ui' show Locale, PlatformDispatcher;

import '../gen_l10n/app_localizations.dart';
import 'i18n_language.dart';

/// 在没有 `BuildContext` 的地方取一份 [AppLocalizations]。
///
/// Service 和 Agent 工具拿不到 context，但它们交给模型的文案（天气、时间段这类
/// 枚举 key）同样要跟着用户的语言走——否则界面显示「多云」，喂给 AI 的却是
/// `partly_cloudy`，模型回信时只能照抄那个英文 key。
///
/// [localeCode] 传 `SettingsService.localeCode`；为空表示跟随系统。不在支持列表里
/// 的语言退回英文，和 `MaterialApp` 的 `supportedLocales` 协商结果一致。
AppLocalizations resolveAppLocalizations(String? localeCode) {
  // 设置里存的可能是 'zh_CN' 这种带区域的写法（`SettingsService.setLocale`
  // 接受它），而 supportedLocales 比的是纯语言子标签。不先归一化，zh_CN 的
  // 用户会被判成"不支持"一路掉到英文。
  //
  // 只借 I18nLanguage.base 做归一化，不用它的 appLanguage：那份 supported
  // 集合是给地理编码 API 用的，少了 de 和 es，套在这里会把这两种语言的用户
  // 也送去英文。支持与否一律以 AppLocalizations.supportedLocales 为准。
  final languageCode = localeCode == null || localeCode.trim().isEmpty
      ? PlatformDispatcher.instance.locale.languageCode.toLowerCase()
      : I18nLanguage.base(localeCode);

  final supported = AppLocalizations.supportedLocales
      .map((locale) => locale.languageCode)
      .toSet();

  return lookupAppLocalizations(
    Locale(supported.contains(languageCode) ? languageCode : 'en'),
  );
}
