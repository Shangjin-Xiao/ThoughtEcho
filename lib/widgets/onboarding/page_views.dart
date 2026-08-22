import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../models/onboarding_models.dart';
import '../../config/onboarding_config.dart';
import '../../controllers/onboarding_controller.dart';
import '../../services/settings_service.dart';
import '../../services/location_service.dart';
import '../../theme/theme_style.dart';

/// 欢迎页面：应用图标、一句话定位，和唯一一个要在这一屏做的决定——语言。
///
/// 语言不铺成选项列表：8 个选项里绝大多数人用「跟随系统」，摊开只会让第一屏变吵。
/// 收成一行「语言 · 当前值 ›」，点开才是完整列表；当前值用母语原文
/// （[OnboardingConfig.nativeLanguageLabel]），这样界面语言看不懂的人也能认出自己那一项。
class WelcomePageView extends StatefulWidget {
  final OnboardingPageData pageData;

  const WelcomePageView({super.key, required this.pageData});

  @override
  State<WelcomePageView> createState() => _WelcomePageViewState();
}

class _WelcomePageViewState extends State<WelcomePageView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    // 入场不用 easeOutBack：回弹的活泼感和纸墨的克制冲突，平移到位即可。
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String get _currentLanguageCode =>
      context.read<OnboardingController>().state.getPreference<String>(
            'localeCode',
          ) ??
      '';

  void _selectLanguage(String code) {
    final controller = context.read<OnboardingController>();
    controller.updatePreference('localeCode', code);

    // 立即生效：这一屏之后的所有文案都应该已经是新语言。
    context.read<SettingsService>().setLocale(code.isEmpty ? null : code);
    context.read<LocationService>().currentLocaleCode =
        code.isEmpty ? null : code;
  }

  Future<void> _openLanguageSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => _LanguageSheet(
        selectedCode: _currentLanguageCode,
      ),
    );

    if (selected == null || !mounted) return;
    _selectLanguage(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildAppIcon(theme),
                const SizedBox(height: 32),
                Text(
                  widget.pageData.title,
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.pageData.subtitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                _buildLanguageTile(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 语言行：整行可点，右侧是当前值和一个指示可展开的箭头。
  Widget _buildLanguageTile(ThemeData theme) {
    final shape = AppShapeTokens.of(context);
    final l10n = AppLocalizations.of(context);
    // 语言变了这一行要跟着变，所以这里要 watch 而不是 read。
    final code = context
            .watch<OnboardingController>()
            .state
            .getPreference<String>('localeCode') ??
        '';

    return Semantics(
      button: true,
      label: l10n.prefLanguage,
      value: OnboardingConfig.languageDisplayLabel(l10n, code),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(shape.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(shape.cardRadius),
          onTap: _openLanguageSheet,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(shape.cardRadius),
              border: shape.borderWidth > 0
                  ? Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: shape.borderWidth,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Icon(
                  Icons.translate_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Text(
                  l10n.prefLanguage,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    OnboardingConfig.languageDisplayLabel(l10n, code),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppIcon(ThemeData theme) {
    final shape = AppShapeTokens.of(context);
    final radius = BorderRadius.circular(shape.cardRadius);

    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shape.lowShadow,
        border: shape.borderWidth > 0
            ? Border.all(
                color: theme.colorScheme.outlineVariant,
                width: shape.borderWidth,
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          'assets/icon.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return ColoredBox(
              color: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.auto_stories,
                size: 56,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 语言选择底部弹窗。选中项走 pop 返回，由调用方落地，弹窗本身不碰服务。
class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.selectedCode});

  final String selectedCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Text(
              l10n.onboardingSelectLanguage,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final code in OnboardingConfig.languageCodes)
                  _LanguageOptionTile(
                    code: code,
                    selected: code == selectedCode,
                    onTap: () => Navigator.of(context).pop(code),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        onTap: onTap,
        title: Text(
          OnboardingConfig.languageDisplayLabel(l10n, code),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: selected ? theme.colorScheme.primary : null,
            fontWeight: selected ? FontWeight.w600 : null,
          ),
        ),
        trailing: selected
            ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    );
  }
}
