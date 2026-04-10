import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';
import '../services/api_service.dart';

class ApiNinjasCategorySelectionPage extends StatefulWidget {
  final List<String> initialSelectedCategories;

  const ApiNinjasCategorySelectionPage({
    super.key,
    required this.initialSelectedCategories,
  });

  @override
  State<ApiNinjasCategorySelectionPage> createState() =>
      _ApiNinjasCategorySelectionPageState();
}

class _ApiNinjasCategorySelectionPageState
    extends State<ApiNinjasCategorySelectionPage> {
  late final TextEditingController _searchController;
  late final Set<String> _selectedCategories;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedCategories = widget.initialSelectedCategories.toSet();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _popWithSelection() {
    Navigator.of(context).pop(_selectedCategories.toList());
  }

  void _toggleCategory(String categoryKey) {
    setState(() {
      if (_selectedCategories.contains(categoryKey)) {
        _selectedCategories.remove(categoryKey);
      } else {
        _selectedCategories.add(categoryKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final categoryEntries = _filteredCategories(l10n);

    return PopScope<List<String>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _popWithSelection();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.dailyQuoteApiNinjasCategorySelection),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _popWithSelection,
          ),
          actions: [
            if (_selectedCategories.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(_selectedCategories.clear);
                },
                child: Text(l10n.clearAll),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.trim().toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: l10n.dailyQuoteApiNinjasCategorySearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _selectedCategories.isEmpty
                      ? l10n.dailyQuoteApiNinjasAllCategoriesUsed
                      : l10n.dailyQuoteApiNinjasSelectedCount(
                          _selectedCategories.length,
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: categoryEntries.isEmpty
                  ? Center(
                      child: Text(
                        l10n.dailyQuoteApiNinjasNoCategoriesFound,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: categoryEntries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = categoryEntries[index];
                        final isSelected = _selectedCategories.contains(
                          entry.key,
                        );

                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            onTap: () => _toggleCategory(entry.key),
                            title: Text(entry.value),
                            subtitle: Text(entry.key),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<MapEntry<String, String>> _filteredCategories(AppLocalizations l10n) {
    final categories = ApiService.getApiNinjasCategories(l10n).entries.toList();
    if (_searchQuery.isEmpty) {
      return categories;
    }

    return categories.where((entry) {
      return entry.key.toLowerCase().contains(_searchQuery) ||
          entry.value.toLowerCase().contains(_searchQuery);
    }).toList();
  }
}
