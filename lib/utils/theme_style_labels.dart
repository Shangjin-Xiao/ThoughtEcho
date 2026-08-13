import '../gen_l10n/app_localizations.dart';
import '../theme/theme_style.dart';

/// 主题风格的显示名与一句说明。
///
/// 放在这里而不是挂到 [ThemeStyle] 上，是为了让枚举保持与 l10n 无关。
/// switch 是穷尽的：加新风格时这里会编译报错，提醒补文案。
(String name, String description) themeStyleLabel(
  AppLocalizations l10n,
  ThemeStyle style,
) =>
    switch (style) {
      ThemeStyle.material => (
          l10n.themeStyleMaterial,
          l10n.themeStyleMaterialDesc,
        ),
      ThemeStyle.paper => (l10n.themeStylePaper, l10n.themeStylePaperDesc),
      ThemeStyle.plain => (l10n.themeStylePlain, l10n.themeStylePlainDesc),
    };

/// 墨色的显示名。同上：switch 穷尽，加新墨色时这里会编译报错。
String themeAccentLabel(AppLocalizations l10n, ThemeAccent accent) =>
    switch (accent) {
      ThemeAccent.umber => l10n.themeAccentUmber,
      ThemeAccent.celadon => l10n.themeAccentCeladon,
      ThemeAccent.indigo => l10n.themeAccentIndigo,
      ThemeAccent.cinnabar => l10n.themeAccentCinnabar,
    };
