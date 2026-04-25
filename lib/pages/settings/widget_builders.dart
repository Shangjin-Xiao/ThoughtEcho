part of '../settings_page.dart';

/// Extension containing widget builder methods
extension _WidgetBuilders on SettingsPageState {
  String _retentionLabel(AppLocalizations l10n, int days) {
    switch (days) {
      case 7:
        return l10n.trashRetentionOption7Days;
      case 90:
        return l10n.trashRetentionOption90Days;
      case 30:
      default:
        return l10n.trashRetentionOption30Days;
    }
  }

  // --- 新增：构建关于对话框中链接的辅助方法 ---
  Widget _buildAboutLink({
    required BuildContext context,
    required IconData icon,
    required String text,
    required String url,
  }) {
    return Center(
      child: ElevatedButton.icon(
        style: _primaryButtonStyle(context),
        onPressed: () => _launchUrl(url),
        icon: Icon(icon, size: 18),
        label: Text(text),
      ),
    );
  }

  // 统一按钮样式方法，作为类的私有工具方法，便于在文件内复用
  ButtonStyle _primaryButtonStyle(BuildContext context) =>
      ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  ButtonStyle _textButtonStyle(BuildContext context) =>
      TextButton.styleFrom(minimumSize: const Size.fromHeight(44));

  // 构建语言设置项
  Widget _buildLanguageItem(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final currentLocale = settingsService.localeCode;
    final l10n = AppLocalizations.of(context);

    String getLanguageName(String? code) {
      switch (code) {
        case 'zh':
          return l10n.languageChinese;
        case 'en':
          return l10n.languageEnglish;
        case 'ja':
          return l10n.languageJapanese;
        case 'ko':
          return l10n.languageKorean;
        case 'es':
          return l10n.languageSpanish;
        case 'fr':
          return l10n.languageFrench;
        case 'de':
          return l10n.languageGerman;
        default:
          return l10n.languageFollowSystem;
      }
    }

    return ListTile(
      title: Text(l10n.languageSettings),
      subtitle: Text(getLanguageName(currentLocale)),
      leading: const Icon(Icons.translate),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.selectLanguage),
            content: StatefulBuilder(
              builder: (context, setState) {
                return RadioGroup<String?>(
                  groupValue: currentLocale,
                  onChanged: (value) async {
                    await settingsService.setLocale(value);
                    // 同步更新位置服务的语言设置
                    locationService.currentLocaleCode = value;
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String?>(
                        title: Text(l10n.languageFollowSystem),
                        value: null,
                      ),
                      RadioListTile<String?>(
                        title: Text(l10n.languageChinese),
                        value: 'zh',
                      ),
                      RadioListTile<String?>(
                        title: const Text('English'),
                        value: 'en',
                      ),
                      RadioListTile<String?>(
                        title: const Text('日本語'),
                        value: 'ja',
                      ),
                      RadioListTile<String?>(
                        title: const Text('한국어'),
                        value: 'ko',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Español'),
                        value: 'es',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Français'),
                        value: 'fr',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Deutsch'),
                        value: 'de',
                      ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        );
      },
    );
  }

  // 构建默认启动页面设置项
  Widget _buildDefaultStartPageItem(BuildContext context) {
    // 从 SettingsService 获取设置
    final settingsService = Provider.of<SettingsService>(context);
    final currentValue = settingsService.appSettings.defaultStartPage;
    final l10n = AppLocalizations.of(context);

    return ListTile(
      key: _startupPageGuideKey, // 功能引导 key
      title: Text(l10n.settingsDefaultStartPage),
      subtitle: Text(
        currentValue == 0
            ? l10n.settingsStartPageHome
            : l10n.settingsStartPageNotes,
      ),
      leading: const Icon(Icons.home_outlined),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.settingsSelectStartPage),
            content: StatefulBuilder(
              builder: (context, setState) {
                return RadioGroup<int>(
                  groupValue: currentValue,
                  onChanged: (value) {
                    if (value != null) {
                      settingsService.updateAppSettings(
                        settingsService.appSettings.copyWith(
                          defaultStartPage: value,
                        ),
                      );
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<int>(
                        title: Text(l10n.settingsStartPageHome),
                        value: 0,
                      ),
                      RadioListTile<int>(
                        title: Text(l10n.settingsStartPageNotes),
                        value: 1,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // --- 一周年庆典横幅 ---
  Widget _buildAnniversaryBanner(BuildContext context) {
    final now = DateTime.now();
    final settingsService = context.read<SettingsService>();
    final shouldShow = AnniversaryDisplayUtils.shouldShowSettingsBanner(
      now: now,
      developerMode: settingsService.appSettings.developerMode,
    );
    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFF8FAFC), const Color(0xFFEEF2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showAnniversaryAnimationInSettings(context),
          child: Stack(
            children: [
              // 背景装饰 - 柔和的光晕
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFF818CF8,
                        ).withValues(alpha: isDark ? 0.2 : 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: -40,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFF60A5FA,
                        ).withValues(alpha: isDark ? 0.15 : 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 主内容区
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // 左侧：精致的笔记本图标
                    const AnniversaryNotebookIcon(),
                    const SizedBox(width: 20),
                    // 右侧：文本和指示器
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.anniversaryBannerTitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: isDark
                                  ? const Color(0xFFF8FAFC)
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formatAnniversaryBannerSubtitleForTile(
                              l10n.anniversaryBannerSubtitle,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF475569),
                              height: 1.4,
                            ),
                            softWrap: true,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                l10n.anniversaryBannerTap,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF818CF8)
                                      : const Color(0xFF4F46E5),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: isDark
                                    ? const Color(0xFF818CF8)
                                    : const Color(0xFF4F46E5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnniversaryAnimationInSettings(BuildContext context) {
    showAnniversaryAnimationOverlay(context);
  }
}
