import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import '../gen_l10n/app_localizations.dart';

/// 许可证页面
/// 显示应用使用的第三方资源许可信息
class LicensePage extends StatefulWidget {
  const LicensePage({super.key});

  @override
  State<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<LicensePage> {
  // 页面当前为静态内容展示，已移除未使用的搜索/加载逻辑以减少无效状态与 lint 警告。
  String? _licenseText;
  bool _licenseLoading = false;
  String? _licenseError;

  @override
  void initState() {
    super.initState();
    _loadLicenseText();
  }

  Future<void> _loadLicenseText() async {
    setState(() {
      _licenseLoading = true;
      _licenseError = null;
    });
    try {
      // LICENSE 文件需在 pubspec.yaml assets 中声明，或用 rootBundle 读取
      final text = await rootBundle.loadString('LICENSE');
      setState(() {
        _licenseText = text;
        _licenseLoading = false;
      });
    } catch (e) {
      setState(() {
        _licenseError = e.toString();
        _licenseLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.licenseInfo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionCard(
            context,
            title: l10n.appLicense,
            icon: Icons.verified_user_outlined,
            content: _buildLicenseFileSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            title: l10n.openSourceAcknowledgements,
            icon: Icons.code_outlined,
            content: _buildAcknowledgementsSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            title: l10n.lottieAnimationLicense,
            icon: Icons.animation_outlined,
            content: _buildLottieSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            title: l10n.systemLicenses,
            icon: Icons.article_outlined,
            content: _buildSystemLicensesSection(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseFileSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ElevatedButton.icon(
      icon: const Icon(Icons.verified_user_outlined),
      label: Text(l10n.viewAppLicense),
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      onPressed: () => _showLicenseDialog(context),
    );
  }

  Future<void> _showLicenseDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        if (_licenseLoading) {
          return AlertDialog(
            title: Text(l10n.appLicense),
            content: const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (_licenseError != null) {
          return AlertDialog(
            title: Text(l10n.appLicense),
            content: Text(
              l10n.loadLicenseFailed(_licenseError!),
              style: const TextStyle(color: Colors.red),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.close),
              ),
            ],
          );
        }
        if (_licenseText == null || _licenseText!.trim().isEmpty) {
          return AlertDialog(
            title: Text(l10n.appLicense),
            content: Text(l10n.licenseFileNotFound),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.close),
              ),
            ],
          );
        }
        return AlertDialog(
          title: Text(l10n.appLicense),
          content: SizedBox(
            width: 400,
            height: 320,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: SelectableText(
                  _licenseText!,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildLottieSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.lottieFilesCredits, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
        _buildLottieAttribution(
          context: context,
          title: l10n.searchLoadingAnimation,
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/search-loading',
        ),
        _buildLottieAttribution(
          context: context,
          title: l10n.weatherSearchAnimation,
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/weather-search',
        ),
        _buildLottieAttribution(
          context: context,
          title: l10n.aiThinkingAnimation,
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/ai-loading',
        ),
        _buildLottieAttribution(
          context: context,
          title: l10n.noResultsAnimation,
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/not-found',
        ),
        const SizedBox(height: 12),
        Text(
          l10n.thankLottieFiles,
          style: const TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildAcknowledgementsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.openSourceDesc, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
        // 列出库并附带许可证与链接（以上游仓库/包管理页面为准）
        _buildAttributionRow(
          context: context,
          title: l10n.framework,
          name: 'Flutter',
          url: 'https://github.com/flutter/flutter',
          description: 'BSD-3-Clause',
        ),
        _buildAttributionRow(
          context: context,
          title: l10n.stateManagement,
          name: 'Provider',
          url: 'https://pub.dev/packages/provider',
          description: 'MIT',
        ),
        _buildAttributionRow(
          context: context,
          title: l10n.animationSupport,
          name: 'Lottie (lottie_flutter / lottie)',
          url: 'https://pub.dev/packages/lottie',
          description: 'MIT',
        ),
        _buildAttributionRow(
          context: context,
          title: l10n.localStorage,
          name: 'MMKV',
          url: 'https://github.com/Tencent/MMKV',
          description: 'BSD-3-Clause',
        ),
        // 同步功能相关鸣谢
        Text(
          l10n.syncIntegrationNote,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        _buildAttributionRow(
          context: context,
          title: l10n.noteSync,
          name: 'LocalSend',
          url: 'https://github.com/localsend/localsend',
          description: 'Apache 2.0',
        ),
        const SizedBox(height: 12),
        Text(
          l10n.serviceApiAcknowledgements,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildAttributionRow(
          context: context,
          title: l10n.weatherData,
          name: 'Open-Meteo',
          url: 'https://open-meteo.com/',
          description: null,
        ),
        _buildAttributionRow(
          context: context,
          title: l10n.dailyQuoteApi,
          name: 'Hitokoto (v1.hitokoto.cn)',
          url: 'https://hitokoto.cn/',
          description: null,
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => _launchUrl(
            'https://flutter.dev/docs/development/packages-and-plugins/using-packages',
          ),
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.viewFullDependencyList),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.thankOpenSourceContributors,
          style: const TextStyle(fontSize: 12, color: Color(0xB3000000)),
        ),
      ],
    );
  }

  Widget _buildAttributionRow({
    required BuildContext context,
    required String title,
    required String name,
    required String url,
    String? description,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title: $name',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(fontSize: 12)),
                ],
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchUrl(url),
                  child: Text(
                    url,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemLicensesSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 改为一个按钮，点击后跳转到单独的系统许可证页面（按需渲染，避免当前页面一次性构建大量条目）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.systemLicensesDesc, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProgressiveSystemLicensesPage(),
              ),
            );
          },
          icon: const Icon(Icons.article_outlined),
          label: Text(l10n.viewSystemLicenses),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
        ),
      ],
    );
  }

  Widget _buildLottieAttribution({
    required BuildContext context,
    required String title,
    required String creator,
    required String url,
  }) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          const Icon(Icons.animation_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                InkWell(
                  onTap: () => _launchUrl(url),
                  child: Text(
                    '${l10n.sourceLabel} $creator',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // 如果无法启动URL，静默失败或显示错误
      debugPrint('无法打开链接: $url');
    }
  }
}

// 顶级辅助函数：在 isolate 中拼接段落文本，避免阻塞 UI
String _joinParagraphs(List<String> parts) => parts.join('\n\n');

/// 单独的系统许可证页面（美化版）
/// 带搜索、计数与按需加载，使用 ExpansionPanelList 管理展开状态
class SystemLicensesPage extends StatefulWidget {
  const SystemLicensesPage({super.key});

  @override
  State<SystemLicensesPage> createState() => _SystemLicensesPageState();
}

class _SystemLicensesPageState extends State<SystemLicensesPage> {
  // 合并后的许可证条目
  List<_MergedLicenseEntry> _mergedEntries = [];

  void _mergeEntries() {
    final Map<String, _MergedLicenseEntry> map = {};
    for (final entry in _entries) {
      for (final pkg in entry.packages) {
        final key = pkg.trim();
        if (!map.containsKey(key)) {
          map[key] = _MergedLicenseEntry([key], List.of(entry.paragraphs));
        } else {
          final exist = map[key]!;
          for (final p in entry.paragraphs) {
            if (!exist.paragraphs.any((ep) => ep.text == p.text)) {
              exist.paragraphs.add(p);
            }
          }
        }
      }
    }
    _mergedEntries = map.values.toList();
  }

  final TextEditingController _searchController = TextEditingController();
  final List<LicenseEntry> _entries = [];
  final Set<int> _expanded = {};
  bool _loading = true;
  String _error = '';
  // 使用缓冲与定时刷新避免大量 setState 导致 UI 冻结
  StreamSubscription<LicenseEntry>? _licenseSub;
  final List<LicenseEntry> _buffer = [];
  Timer? _flushTimer;

  @override
  void initState() {
    super.initState();
    // 延迟到首帧后再开始订阅许可证流，确保页面能先渲染出加载状态，避免长时间同步事件阻塞首帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _licenseSub = LicenseRegistry.licenses.listen(
        (entry) {
          _buffer.add(entry);
          // 启动或重置定时器：每 150ms 刷新一次到 UI
          _flushTimer ??= Timer.periodic(const Duration(milliseconds: 150), (
            _,
          ) {
            if (_buffer.isEmpty) return;
            final toAdd = List<LicenseEntry>.from(_buffer);
            _buffer.clear();
            // 批量添加并触发一次 setState
            if (mounted) {
              setState(() {
                _entries.addAll(toAdd);
                _mergeEntries();
              });
            } else {
              // 如果已卸载则丢弃
              _buffer.clear();
            }
          });
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _error = e.toString();
              _loading = false;
            });
          }
        },
        onDone: () {
          // 刷新剩余 buffer 然后停止定时器
          if (_buffer.isNotEmpty) {
            final toAdd = List<LicenseEntry>.from(_buffer);
            _buffer.clear();
            if (mounted) {
              setState(() {
                _entries.addAll(toAdd);
                _mergeEntries();
              });
            }
          }
          _flushTimer?.cancel();
          _flushTimer = null;
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
        },
      );
    });
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _licenseSub?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }

  List<int> _filteredIndexes() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return List<int>.generate(_mergedEntries.length, (i) => i);
    final result = <int>[];
    for (var i = 0; i < _mergedEntries.length; i++) {
      final e = _mergedEntries[i];
      final packages = e.packages.join(', ').toLowerCase();
      if (packages.contains(q)) {
        result.add(i);
        continue;
      }
      if (e.paragraphs.isNotEmpty &&
          e.paragraphs.first.text.toLowerCase().contains(q)) {
        result.add(i);
      }
    }
    return result;
  }

  void _toggleExpandAll(List<int> visible) {
    final allExpanded = visible.every((i) => _expanded.contains(i));
    setState(() {
      if (allExpanded) {
        _expanded.clear();
      } else {
        _expanded.addAll(visible);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = _filteredIndexes();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.systemLicenses),
            if (!_loading && _error.isEmpty)
              Text(
                l10n.licenseEntriesCount(visible.length, _entries.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.expandCollapseAll,
            icon: const Icon(Icons.unfold_more),
            onPressed: _loading ? null : () => _toggleExpandAll(visible),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.blueGrey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.licensePageDesc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchPackageOrLicense,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(visible)),
        ],
      ),
    );
  }

  Widget _buildBody(List<int> visible) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 12),
            Text(
              l10n.loadSystemLicensesFailed(_error),
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      );
    }
    if (_mergedEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, color: Colors.grey, size: 32),
            const SizedBox(height: 12),
            Text(
              l10n.noSystemLicensesFound,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(
          l10n.noMatchingLicensesFound,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final entryIndex = visible[index];
        final entry = _mergedEntries[entryIndex];
        final packages = entry.packages.join(', ');
        final preview = entry.paragraphs.isNotEmpty
            ? entry.paragraphs.first.text
            : l10n.noLicenseContent;
        final initials = packages.isNotEmpty
            ? packages.trim()[0].toUpperCase()
            : 'P';
        final isExpanded = _expanded.contains(entryIndex);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              radius: 18,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Text(
              packages.isEmpty ? l10n.unnamed : packages,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              preview.length > 120 ? '${preview.substring(0, 120)}…' : preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).textTheme.bodySmall?.color?.withValues(alpha: 0.9),
              ),
            ),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (open) {
              setState(() {
                if (open) {
                  _expanded.add(entryIndex);
                } else {
                  _expanded.remove(entryIndex);
                }
              });
            },
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 6.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: l10n.copyLicense,
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final paragraphs = entry.paragraphs
                            .map((p) => p.text)
                            .toList();
                        final full = await compute(_joinParagraphs, paragraphs);
                        if (!mounted) return;
                        await Clipboard.setData(ClipboardData(text: full));
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.licenseCopied),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: FutureBuilder<String>(
                  future: compute(
                    _joinParagraphs,
                    entry.paragraphs.map((p) => p.text).toList(),
                  ),
                  builder: (c, s) {
                    if (!s.hasData) {
                      return const SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return SelectableText(s.data!);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MergedLicenseEntry {
  final List<String> packages;
  final List<LicenseParagraph> paragraphs;
  _MergedLicenseEntry(this.packages, this.paragraphs);
}

/// 渐进式加载的系统许可证页面：初始只显示一条，展开任意一条时自动展示下一条（避免一次性渲染大量条目）
class ProgressiveSystemLicensesPage extends StatefulWidget {
  const ProgressiveSystemLicensesPage({super.key});

  @override
  State<ProgressiveSystemLicensesPage> createState() =>
      _ProgressiveSystemLicensesPageState();
}

class _ProgressiveSystemLicensesPageState
    extends State<ProgressiveSystemLicensesPage> {
  List<LicenseEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 一次性读取所有系统许可证条目，但不在列表中渲染完整文本
    LicenseRegistry.licenses
        .toList()
        .then((list) {
          setState(() {
            _entries = list;
            _loading = false;
          });
        })
        .catchError((e) {
          setState(() {
            _entries = [];
            _error = e.toString();
            _loading = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.systemLicenses)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(l10n.loadSystemLicensesFailed(_error!)));
    }
    if (_entries.isEmpty) {
      return Center(child: Text(l10n.noSystemLicensesFound));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final packages = entry.packages.join(', ');
        final preview = entry.paragraphs.isNotEmpty
            ? entry.paragraphs.first.text
            : l10n.noLicenseContent;
        final initials = packages.isNotEmpty
            ? packages.trim()[0].toUpperCase()
            : 'P';

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LicenseDetailPage(
                  entry: entry,
                  title: packages.isEmpty ? l10n.unnamed : packages,
                ),
              ),
            );
          },
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    radius: 20,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          packages.isEmpty ? l10n.unnamed : packages,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          preview.length > 140
                              ? '${preview.substring(0, 140)}…'
                              : preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color
                                ?.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class LicenseDetailPage extends StatelessWidget {
  final LicenseEntry entry;
  final String title;
  const LicenseDetailPage({
    super.key,
    required this.entry,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: compute(
          _joinParagraphs,
          entry.paragraphs.map((p) => p.text).toList(),
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(l10n.loadLicenseFailed(snapshot.error.toString())),
            );
          }
          final text = snapshot.data ?? l10n.noLicenseContent;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(text, style: const TextStyle(height: 1.4)),
          );
        },
      ),
    );
  }
}
