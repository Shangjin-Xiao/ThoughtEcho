import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/theme/app_theme.dart';

/// Data model for a chapter in the user guide
class GuideChapter {
  final String id;
  final String title;
  final IconData icon;
  final List<GuideSection> sections;
  bool isExpanded;

  GuideChapter({
    required this.id,
    required this.title,
    required this.icon,
    required this.sections,
    this.isExpanded = false,
  });
}

/// Data model for a section within a chapter
class GuideSection {
  final String title;
  final List<String> items;

  GuideSection({required this.title, required this.items});
}

class UserGuidePage extends StatefulWidget {
  const UserGuidePage({super.key});

  @override
  State<UserGuidePage> createState() => _UserGuidePageState();
}

class _UserGuidePageState extends State<UserGuidePage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  List<GuideChapter> _chapters = [];
  List<GuideChapter> _filteredChapters = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String? _error;

  // Keys for scrolling to chapters
  final Map<String, GlobalKey> _chapterKeys = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chapters.isEmpty) {
      _loadManual();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadManual() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final locale = Localizations.localeOf(context);
      final isZh = locale.languageCode == 'zh';

      // Load content from the single source of truth
      final String fullContent = await rootBundle.loadString(
        'docs/USER_MANUAL.md',
      );

      // Extract the language-specific block
      final String langMarker = isZh
          ? '<div id="-中文版本">'
          : '<div id="-english-version">';
      final int startIndex = fullContent.indexOf(langMarker);
      if (startIndex == -1) {
        throw Exception('Language block not found: $langMarker');
      }

      final int contentStart = startIndex + langMarker.length;
      final int endIndex = fullContent.indexOf('</div>', contentStart);
      final String block = endIndex != -1
          ? fullContent.substring(contentStart, endIndex)
          : fullContent.substring(contentStart);

      // Parse the block into chapters
      final parsedChapters = _parseMarkdown(block);

      if (mounted) {
        setState(() {
          _chapters = parsedChapters;

          // Initialize GlobalKeys for scrolling
          for (var chapter in _chapters) {
            if (!_chapterKeys.containsKey(chapter.id)) {
              _chapterKeys[chapter.id] = GlobalKey();
            }
          }

          _filterChapters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  List<GuideChapter> _parseMarkdown(String content) {
    final List<GuideChapter> chapters = [];
    final List<String> lines = content.split('\n');

    GuideChapter? currentChapter;
    GuideSection? currentSection;

    // Helper for icons based on chapter title/index
    IconData getIcon(String title, int index) {
      final t = title.toLowerCase();
      if (t.contains('快速') || t.contains('started')) {
        return Icons.rocket_launch_outlined;
      }
      if (t.contains('ai')) {
        return Icons.auto_awesome_outlined;
      }
      if (t.contains('编辑器') || t.contains('editor')) {
        return Icons.edit_note_outlined;
      }
      if (t.contains('管理') || t.contains('management')) {
        return Icons.library_books_outlined;
      }
      if (t.contains('同步') || t.contains('sync')) {
        return Icons.sync_outlined;
      }
      if (t.contains('备份') || t.contains('backup')) {
        return Icons.backup_outlined;
      }
      if (t.contains('设置') || t.contains('settings')) {
        return Icons.tune_outlined;
      }
      if (t.contains('常见') || t.contains('faq')) {
        return Icons.help_outline_rounded;
      }

      final defaults = [
        Icons.info_outline,
        Icons.settings_suggest_outlined,
        Icons.edit_outlined,
        Icons.list_alt,
        Icons.auto_awesome,
        Icons.sync,
        Icons.save_as,
        Icons.tune,
        Icons.help_center,
      ];
      return defaults[index % defaults.length];
    }

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Chapter: ## N. Title
      if (trimmed.startsWith('## ')) {
        final title = trimmed
            .substring(3)
            .replaceFirst(RegExp(r'^\d+\.\s*'), '');
        currentChapter = GuideChapter(
          id: 'chapter_${chapters.length}',
          title: title,
          icon: getIcon(title, chapters.length),
          sections: [],
        );
        chapters.add(currentChapter);
        currentSection = null;
        continue;
      }

      if (currentChapter == null) continue;

      // Section: ### Title
      if (trimmed.startsWith('### ')) {
        currentSection = GuideSection(title: trimmed.substring(4), items: []);
        currentChapter.sections.add(currentSection);
        continue;
      }

      // Items: - Item or 1. Item
      if (trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          RegExp(r'^\d+\. ').hasMatch(trimmed)) {
        if (currentSection == null) {
          currentSection = GuideSection(title: '', items: []);
          currentChapter.sections.add(currentSection);
        }
        String itemText = trimmed;
        if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
          itemText = trimmed.substring(2);
        } else {
          itemText = trimmed.replaceFirst(RegExp(r'^\d+\.\s*'), '');
        }
        itemText = itemText
            .replaceAll('**', '')
            .replaceAll('*', '')
            .replaceAll('`', '');
        currentSection.items.add(itemText);
        continue;
      }

      // Tables
      if (trimmed.startsWith('|')) {
        if (trimmed.contains('---')) continue;
        final cells = trimmed
            .split('|')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList();
        if (cells.length >= 2) {
          if (currentSection == null) {
            currentSection = GuideSection(title: '', items: []);
            currentChapter.sections.add(currentSection);
          }
          currentSection.items.add('${cells[0]}: ${cells[1]}');
        }
        continue;
      }

      // FAQ and other text
      if (!trimmed.startsWith('#') &&
          !trimmed.startsWith('>') &&
          !trimmed.startsWith('!')) {
        if (currentSection != null || currentChapter.sections.isNotEmpty) {
          if (trimmed.startsWith('Q:') || trimmed.startsWith('**Q:')) {
            currentSection = GuideSection(
              title: trimmed.replaceAll('**', ''),
              items: [],
            );
            currentChapter.sections.add(currentSection);
          } else if (trimmed.startsWith('A:') || trimmed.startsWith('**A:')) {
            currentSection?.items.add(trimmed.replaceAll('**', ''));
          } else if (trimmed.length < 200) {
            if (currentSection == null) {
              currentSection = GuideSection(title: '', items: []);
              currentChapter.sections.add(currentSection);
            }
            currentSection.items.add(trimmed);
          }
        }
      }
    }
    return chapters;
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
          _filterChapters();
        });
      }
    });
  }

  void _filterChapters() {
    if (_searchQuery.isEmpty) {
      _filteredChapters = List.from(_chapters);
    } else {
      _filteredChapters = [];
      for (var chapter in _chapters) {
        bool chapterMatches = chapter.title.toLowerCase().contains(
          _searchQuery,
        );
        List<GuideSection> matchingSections = [];

        for (var section in chapter.sections) {
          bool sectionMatches = section.title.toLowerCase().contains(
            _searchQuery,
          );
          bool itemMatches = section.items.any(
            (item) => item.toLowerCase().contains(_searchQuery),
          );

          if (chapterMatches || sectionMatches || itemMatches) {
            matchingSections.add(section);
          }
        }

        if (matchingSections.isNotEmpty) {
          var filteredChapter = GuideChapter(
            id: chapter.id,
            title: chapter.title,
            icon: chapter.icon,
            sections: chapter.sections,
            isExpanded: true,
          );
          _filteredChapters.add(filteredChapter);
        }
      }
    }
  }

  Future<void> _launchOnlineDocs() async {
    final l10n = AppLocalizations.of(context);
    const url = 'https://shangjin-xiao.github.io/ThoughtEcho/user-guide.html';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.cannotOpenLink(url))));
      }
    }
  }

  void _scrollToChapter(String chapterId) {
    final key = _chapterKeys[chapterId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.04,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadManual,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            )
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar.medium(
                  title: Text(l10n.userGuide),
                  centerTitle: true,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new),
                      tooltip: l10n.userGuideOnlineDoc,
                      onPressed: _launchOnlineDocs,
                    ),
                  ],
                ),

                // Search Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SearchBar(
                      controller: _searchController,
                      hintText: l10n.userGuideSearchHint,
                      leading: const Icon(Icons.search),
                      trailing: _searchController.text.isNotEmpty
                          ? [
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => _searchController.clear(),
                              ),
                            ]
                          : null,
                      elevation: WidgetStateProperty.all(0),
                      backgroundColor: WidgetStateProperty.all(
                        colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),

                // Chapter Chips Navigation
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: _chapters.map((chapter) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(chapter.title),
                            avatar: Icon(chapter.icon, size: 18),
                            selected: false,
                            onSelected: (_) => _scrollToChapter(chapter.id),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide.none,
                            backgroundColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            labelStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Content
                if (_filteredChapters.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 64,
                            color: colorScheme.outline.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.userGuideNoResults,
                            style: TextStyle(
                              color: colorScheme.outline,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      child: Column(
                        children: _filteredChapters.map((chapter) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              key: _chapterKeys[chapter.id],
                              elevation: 0,
                              color: colorScheme.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.cardRadius,
                                ),
                                side: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Theme(
                                data: theme.copyWith(
                                  dividerColor: Colors.transparent,
                                ),
                                child: ExpansionTile(
                                  initiallyExpanded: chapter.isExpanded,
                                  shape: const Border(),
                                  collapsedShape: const Border(),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      chapter.icon,
                                      color: colorScheme.onPrimaryContainer,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    chapter.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                      fontSize: 16,
                                    ),
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  expandedCrossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: chapter.sections.map((section) {
                                    return _buildSection(
                                      context,
                                      section,
                                      colorScheme,
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    GuideSection section,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty)
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Text(
                    section.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          if (section.title.isNotEmpty) const SizedBox(height: 8),
          ...section.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
