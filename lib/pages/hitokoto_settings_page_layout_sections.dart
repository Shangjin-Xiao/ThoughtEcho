part of 'hitokoto_settings_page.dart';

extension _HitokotoSettingsPageLayoutSections on _HitokotoSettingsPageState {
  Widget _buildHeaderCard({
    required BuildContext context,
    required AppLocalizations l10n,
    required bool showHitokotoTypeSelection,
    required int selectedTypeCount,
    required String providerLabel,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
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
                          ? l10n.selectedCount(selectedTypeCount)
                          : providerLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer.withAlpha(180),
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
    );
  }

  Widget _buildProviderSelectionCard({
    required BuildContext context,
    required AppLocalizations l10n,
    required Map<String, String> providerLabels,
    required String selectedProvider,
    required Set<String> providerCapabilities,
    required ValueChanged<String> onProviderSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
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
                selected: selectedProvider == entry.key,
                onSelected: (selected) {
                  if (selected && selectedProvider != entry.key) {
                    onProviderSelected(entry.key);
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
    );
  }

  Widget _buildTypeActionsRow({
    required BuildContext context,
    required AppLocalizations l10n,
    required VoidCallback onSelectAll,
    required VoidCallback onClearAll,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.select_all_rounded,
            label: l10n.selectAll,
            onPressed: onSelectAll,
            isPrimary: false,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            context: context,
            icon: Icons.deselect_rounded,
            label: l10n.clearAll,
            onPressed: onClearAll,
            isPrimary: false,
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSelectionCard({
    required BuildContext context,
    required AppLocalizations l10n,
    required List<String> selectedTypes,
    required void Function(String type, bool selected) onTypeSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
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
            children: ApiService.getHitokotoTypes(l10n).entries.map((entry) {
              final isSelected = selectedTypes.contains(entry.key);
              return _buildTypeChip(
                context: context,
                type: entry.key,
                label: entry.value,
                isSelected: isSelected,
                onSelected: (selected) => onTypeSelected(entry.key, selected),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTypeSelectionCard({
    required BuildContext context,
    required AppLocalizations l10n,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
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
    );
  }
}
