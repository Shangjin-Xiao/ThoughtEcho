import 'dart:io';

/// 统一的语言参数工具类
/// 为 LocationService 提供一致的语言映射
class I18nLanguage {
  /// 应用支持的语言集合
  static const supported = {'zh', 'en', 'ja', 'ko', 'fr'};

  /// 从 locale 字符串提取基础语言代码
  /// 例如 'zh_CN' -> 'zh', 'en-US' -> 'en', 'fr_FR' -> 'fr'
  static String base(String? localeCode) {
    if (localeCode == null || localeCode.trim().isEmpty) return 'en';
    return localeCode.toLowerCase().split(RegExp(r'[_-]')).first;
  }

  /// 返回应用支持的语言代码，不支持的回退到 'en'
  static String appLanguage(String? localeCode) {
    final b = base(localeCode);
    return supported.contains(b) ? b : 'en';
  }

  /// 优先使用传入的 localeCode，否则回退到系统语言
  static String appLanguageOrSystem(String? localeCode) {
    if (localeCode != null && localeCode.trim().isNotEmpty) {
      return appLanguage(localeCode);
    }
    try {
      return appLanguage(Platform.localeName);
    } catch (_) {
      return 'en';
    }
  }

  /// 构建 HTTP Accept-Language 头，优先请求目标语言，回退到英文
  static String buildAcceptLanguage(String lang) {
    if (lang == 'en') return 'en-US,en;q=0.9';
    final regionMap = {
      'zh': 'zh-CN',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
      'fr': 'fr-FR',
    };
    final primary = regionMap[lang] ?? lang;
    return '$primary,$lang;q=0.9,en;q=0.8';
  }
}
