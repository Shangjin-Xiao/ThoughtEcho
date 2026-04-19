import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../pages/api_ninjas_category_selection_page.dart';
import '../services/api_key_manager.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

part 'hitokoto_settings_page_layout_sections.dart';
part 'hitokoto_settings_page_info_sections.dart';
part 'hitokoto_settings_page_widgets.dart';

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
    final previousHasApiNinjasApiKey = _hasApiNinjasApiKey;
    setState(() {
      _selectedProvider = provider;
      if (provider != ApiService.apiNinjasProvider) {
        _hasApiNinjasApiKey = false;
      }
    });

    try {
      await context.read<SettingsService>().setDailyQuoteProvider(provider);
      if (!mounted) return;

      if (provider == ApiService.apiNinjasProvider) {
        unawaited(_loadApiNinjasApiKeyStatus());
      }

      _showSavedSnackBar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedProvider = previousProvider;
        _hasApiNinjasApiKey = previousHasApiNinjasApiKey;
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
    final l10n = AppLocalizations.of(context);
    final settingsService = context.watch<SettingsService>();
    final providerLabels = ApiService.getDailyQuoteProviders(l10n);
    final apiNinjasCategories = settingsService.apiNinjasCategories;
    final showHitokotoTypeSelection = ApiService.supportsHitokotoTypeSelection(
      _selectedProvider,
    );
    final showProviderCategorySelection =
        ApiService.supportsProviderCategorySelection(
      _selectedProvider,
    );
    final providerLabel =
        providerLabels[_selectedProvider] ?? providerLabels.values.first;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
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
              _buildHeaderCard(
                context: context,
                l10n: l10n,
                showHitokotoTypeSelection: showHitokotoTypeSelection,
                selectedTypeCount: _selectedTypes.length,
                providerLabel: providerLabel,
              ),
              const SizedBox(height: 24),
              _buildProviderSelectionCard(
                context: context,
                l10n: l10n,
                providerLabels: providerLabels,
                onProviderSelected: (provider) {
                  unawaited(_saveSelectedProvider(provider));
                },
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
                _buildTypeActionsRow(
                  context: context,
                  l10n: l10n,
                  onSelectAll: () {
                    setState(() {
                      _selectedTypes
                        ..clear()
                        ..addAll(ApiService.getHitokotoTypes(l10n).keys);
                    });
                    _saveSelectedTypes();
                  },
                  onClearAll: () {
                    setState(() {
                      _selectedTypes
                        ..clear()
                        ..add('a');
                    });
                    _saveSelectedTypes();
                  },
                ),
                const SizedBox(height: 24),
                _buildTypeSelectionCard(
                  context: context,
                  l10n: l10n,
                  selectedTypes: _selectedTypes,
                  onTypeSelected: (type, selected) {
                    setState(() {
                      if (selected) {
                        _selectedTypes.add(type);
                      } else {
                        _selectedTypes.remove(type);
                        if (_selectedTypes.isEmpty) {
                          _selectedTypes.add('a');
                        }
                      }
                    });
                    _saveSelectedTypes();
                  },
                ),
              ] else if (!showProviderCategorySelection) ...[
                const SizedBox(height: 24),
                _buildNoTypeSelectionCard(
                  context: context,
                  l10n: l10n,
                ),
              ],
              if (showHitokotoTypeSelection)
                _buildUsageInstructionsCard(
                  context: context,
                  l10n: l10n,
                ),
              const SizedBox(height: 24),
              _buildProviderAttributionCard(
                context: context,
                l10n: l10n,
                providerLabel: providerLabel,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
