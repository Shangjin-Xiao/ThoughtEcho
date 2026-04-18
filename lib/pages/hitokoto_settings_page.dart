import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../pages/api_ninjas_category_selection_page.dart';
import '../services/api_key_manager.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

class HitokotoSettingsPage extends StatefulWidget {
  const HitokotoSettingsPage({
    super.key,
    this.apiNinjasApiKeyStatusLoader,
  });

  final Future<bool> Function()? apiNinjasApiKeyStatusLoader;

  @override
  State<HitokotoSettingsPage> createState() => _HitokotoSettingsPageState();
}

class _HitokotoSettingsPageState extends State<HitokotoSettingsPage>
    with TickerProviderStateMixin {
  late String _selectedType;
  late String _selectedProvider;
  final List<String> _selectedTypes = [];
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _hasApiNinjasApiKey = false;

  static final Map<String, Set<String>> _providerSupportedCapabilities = {
    ApiService.hitokotoProvider: {'type'},
    ApiService.apiNinjasProvider: {'category', 'apiKey'},
    ApiService.zenQuotesProvider: const {},
    ApiService.meigenProvider: const {},
    ApiService.koreanAdviceProvider: const {},
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0, // 初始值设为1.0，避免闪屏
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _selectedType = context.read<SettingsService>().appSettings.hitokotoType;
    _selectedProvider = context.read<SettingsService>().dailyQuoteProvider;
    // 解析当前选择的类型
    if (_selectedType.contains(',')) {
      _selectedTypes.addAll(_selectedType.split(','));
    } else {
      _selectedTypes.add(_selectedType);
    }

    if (_selectedProvider == ApiService.apiNinjasProvider) {
      unawaited(_loadApiNinjasApiKeyStatus());
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _saveSelectedProvider(String provider) async {
    final previousProvider = _selectedProvider;
    setState(() {
      _selectedProvider = provider;
      if (provider != ApiService.apiNinjasProvider) {
        _hasApiNinjasApiKey = false;
      }
    });
    if (provider == ApiService.apiNinjasProvider) {
      unawaited(_loadApiNinjasApiKeyStatus());
    }
    try {
      await context.read<SettingsService>().setDailyQuoteProvider(provider);
      if (!mounted) return;
      _showSavedSnackBar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedProvider = previousProvider;
      });
      _showSaveFailedSnackBar(e);
    }
  }

  Future<void> _loadApiNinjasApiKeyStatus() async {
    final loader = widget.apiNinjasApiKeyStatusLoader;
    final hasKey = await (loader != null
        ? loader()
        : APIKeyManager().hasValidProviderApiKey(
            ApiService.apiNinjasProvider,
          ));
    if (!mounted) return;

    setState(() {
      _hasApiNinjasApiKey = hasKey;
    });
  }

  Future<void> _configureApiNinjasApiKey() async {
    final l10n = AppLocalizations.of(context);
    final apiKeyManager = APIKeyManager();
    final controller = TextEditingController(
      text: await apiKeyManager.getProviderApiKey(ApiService.apiNinjasProvider),
    );

    if (!mounted) {
      controller.dispose();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.dailyQuoteApiNinjasManageApiKey),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              hintText: l10n.dailyQuoteApiNinjasApiKeyHint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: Text(l10n.clear),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(l10n.add),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (result == null) return;

    final trimmed = result.trim();
    if (trimmed.isNotEmpty && !apiKeyManager.isValidApiKeyFormat(trimmed)) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dailyQuoteApiNinjasApiKeyInvalid)),
      );
      return;
    }

    if (trimmed.isEmpty) {
      await apiKeyManager.removeProviderApiKey(ApiService.apiNinjasProvider);
    } else {
      await apiKeyManager.saveProviderApiKey(
        ApiService.apiNinjasProvider,
        trimmed,
      );
    }

    if (!mounted) return;
    await _loadApiNinjasApiKeyStatus();
    _showSavedSnackBar();
  }

  Future<void> _openApiNinjasCategorySelection() async {
    final settingsService = context.read<SettingsService>();
    final selectedCategories = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ApiNinjasCategorySelectionPage(
          initialSelectedCategories: settingsService.apiNinjasCategories,
        ),
      ),
    );

    if (selectedCategories == null) return;
    await settingsService.setApiNinjasCategories(selectedCategories);
    if (!mounted) return;
    _showSavedSnackBar();
  }

  void _showSavedSnackBar() {
    final l10n = AppLocalizations.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.onInverseSurface,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(l10n.settingsSaved),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSaveFailedSnackBar(Object error) {
    final l10n = AppLocalizations.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.saveFailed(error.toString())),
      ),
    );
  }

  // 保存选择的类型
  void _saveSelectedTypes() {
    // 确保至少选择一种类型
    if (_selectedTypes.isEmpty) {
      _selectedTypes.add('a');
    }
    _selectedType = _selectedTypes.join(',');
    context.read<SettingsService>().updateHitokotoType(_selectedType);
    _showSavedSnackBar();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final settingsService = context.watch<SettingsService>();
    final providerLabels = ApiService.getDailyQuoteProviders(l10n);
    final apiNinjasCategories = settingsService.apiNinjasCategories;
    final showHitokotoTypeSelection = ApiService.supportsHitokotoTypeSelection(
      _selectedProvider,
    );
    final providerLabel =
        providerLabels[_selectedProvider] ?? providerLabels.values.first;
    final providerCapabilities =
        _providerSupportedCapabilities[_selectedProvider] ?? const {};

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(l10n.hitokotoSettings),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部说明卡片
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.primaryContainer.withAlpha(200),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  boxShadow: AppTheme.lightShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.format_quote_rounded,
                            color: colorScheme.onPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                showHitokotoTypeSelection
                                    ? l10n.hitokotoTypeSettings
                                    : l10n.dailyQuoteApi,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                showHitokotoTypeSelection
                                    ? l10n.selectedCount(_selectedTypes.length)
                                    : providerLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onPrimaryContainer
                                      .withAlpha(180),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      showHitokotoTypeSelection
                          ? l10n.hitokotoTypeDesc
                          : l10n.dailyQuoteApiDesc,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer.withAlpha(180),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  border: Border.all(
                    color: colorScheme.outline.withAlpha(50),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dailyQuoteApi,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.dailyQuoteApiDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: providerLabels.entries.map((entry) {
                        return ChoiceChip(
                          label: Text(entry.value),
                          selected: _selectedProvider == entry.key,
                          onSelected: (selected) {
                            if (selected && _selectedProvider != entry.key) {
                              unawaited(_saveSelectedProvider(entry.key));
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.dailyQuoteProviderTypeSupportHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildCapabilityChip(
                          context: context,
                          label: l10n.typeSelection,
                          supported: providerCapabilities.contains('type'),
                        ),
                        _buildCapabilityChip(
                          context: context,
                          label: l10n.dailyQuoteApiNinjasCategorySelection,
                          supported: providerCapabilities.contains('category'),
                        ),
                        _buildCapabilityChip(
                          context: context,
                          label: l10n.dailyQuoteApiNinjasManageApiKey,
                          supported: providerCapabilities.contains('apiKey'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (_selectedProvider == ApiService.apiNinjasProvider) ...[
                const SizedBox(height: 24),
                _buildSettingsEntryCard(
                  context: context,
                  title: l10n.dailyQuoteApiNinjasManageApiKey,
                  subtitle: _hasApiNinjasApiKey
                      ? l10n.dailyQuoteApiNinjasApiKeyConfigured
                      : l10n.dailyQuoteApiNinjasApiKeyMissing,
                  icon: Icons.key_rounded,
                  onTap: _configureApiNinjasApiKey,
                ),
                const SizedBox(height: 16),
                _buildSettingsEntryCard(
                  context: context,
                  title: l10n.dailyQuoteApiNinjasCategorySelection,
                  subtitle: apiNinjasCategories.isEmpty
                      ? l10n.dailyQuoteApiNinjasAllCategoriesUsed
                      : l10n.dailyQuoteApiNinjasSelectedCount(
                          apiNinjasCategories.length,
                        ),
                  icon: Icons.tune_rounded,
                  onTap: _openApiNinjasCategorySelection,
                ),
              ],

              if (showHitokotoTypeSelection) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        context: context,
                        icon: Icons.select_all_rounded,
                        label: l10n.selectAll,
                        onPressed: () {
                          setState(() {
                            _selectedTypes.clear();
                            for (final key in ApiService.getHitokotoTypes(
                              l10n,
                            ).keys) {
                              _selectedTypes.add(key);
                            }
                          });
                          _saveSelectedTypes();
                        },
                        isPrimary: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionButton(
                        context: context,
                        icon: Icons.deselect_rounded,
                        label: l10n.clearAll,
                        onPressed: () {
                          setState(() {
                            _selectedTypes.clear();
                            _selectedTypes.add('a');
                          });
                          _saveSelectedTypes();
                        },
                        isPrimary: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.all(
                      color: colorScheme.outline.withAlpha(50),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.typeSelection,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.typeSelectionHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withAlpha(150),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children:
                            ApiService.getHitokotoTypes(l10n).entries.map((
                          entry,
                        ) {
                          final isSelected = _selectedTypes.contains(entry.key);
                          return _buildTypeChip(
                            context: context,
                            type: entry.key,
                            label: entry.value,
                            isSelected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedTypes.add(entry.key);
                                } else {
                                  _selectedTypes.remove(entry.key);
                                  if (_selectedTypes.isEmpty) {
                                    _selectedTypes.add('a');
                                  }
                                }
                              });
                              _saveSelectedTypes();
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.all(
                      color: colorScheme.outline.withAlpha(30),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    l10n.dailyQuoteProviderNoTypeSelection,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              if (showHitokotoTypeSelection)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.all(
                      color: colorScheme.outline.withAlpha(30),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.usageInstructions,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._buildHelpItems(context, l10n),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // 服务提供商归属说明
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  border: Border.all(
                    color: colorScheme.outline.withAlpha(30),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: colorScheme.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.dailyQuoteServiceProvider(providerLabel),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withAlpha(150),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isPrimary ? colorScheme.primary : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isPrimary
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isPrimary
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip({
    required BuildContext context,
    required String type,
    required String label,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      avatar: isSelected
          ? Icon(Icons.check_rounded, size: 16, color: colorScheme.onPrimary)
          : null,
      labelStyle: TextStyle(
        color:
            isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        fontSize: 13,
      ),
      backgroundColor: colorScheme.surface,
      selectedColor: colorScheme.primary,
      side: BorderSide(
        color: isSelected
            ? colorScheme.primary
            : colorScheme.outline.withAlpha(80),
        width: 1,
      ),
      elevation: isSelected ? 2 : 0,
      shadowColor: colorScheme.shadow.withAlpha(100),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onSelected: onSelected,
    );
  }

  Widget _buildSettingsEntryCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityChip({
    required BuildContext context,
    required String label,
    required bool supported,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: supported
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: supported
              ? colorScheme.primary
              : colorScheme.outline.withAlpha(80),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            supported ? Icons.check_circle_outline : Icons.block,
            size: 14,
            color:
                supported ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            '$label ${supported ? '✓' : '✕'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: supported
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildHelpItems(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final helpItems = [
      l10n.hitokotoHelpItem1,
      l10n.hitokotoHelpItem2,
      l10n.hitokotoHelpItem3,
    ];

    return helpItems.map((item) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withAlpha(180),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
