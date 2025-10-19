import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

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
        _licenseError = '无法加载本程序许可证：$e';
        _licenseLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('许可证信息')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionCard(
            context,
            title: '本程序许可证',
            icon: Icons.verified_user_outlined,
            content: _buildLicenseFileSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            title: '开源库与鸣谢',
            icon: Icons.code_outlined,
            content: _buildAcknowledgementsSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            title: 'Lottie 动画许可',
            icon: Icons.animation_outlined,
            content: _buildLottieSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            title: '系统许可证',
            icon: Icons.article_outlined,
            content: _buildSystemLicensesSection(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseFileSection(BuildContext context) {
    if (_licenseLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_licenseError != null) {
      return Text(_licenseError!, style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
    if (_licenseText == null || _licenseText!.trim().isEmpty) {
      return const Text('未找到本程序 LICENSE 文件。');
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        _licenseText!,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      ),
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
                const Icon(Icons.link_outlined),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '应用使用了来自 LottieFiles 的动画资源：',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        _buildLottieAttribution(
          context: context,
          title: '搜索加载动画',
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/search-loading',
        ),
        _buildLottieAttribution(
          context: context,
          title: '天气搜索动画',
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/weather-search',
        ),
        _buildLottieAttribution(
          context: context,
          title: 'AI思考动画',
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/ai-loading',
        ),
        _buildLottieAttribution(
          context: context,
          title: '搜索无结果动画',
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/not-found',
        ),
        const SizedBox(height: 12),
        Text(
          '感谢 LottieFiles 提供优质的动画资源。',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildAcknowledgementsSection(BuildContext context) {
    // final theme = Theme.of(context); // 已无用，移除
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '本应用基于 Flutter 框架构建，使用并感谢下列开源库与服务：',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        // 列出库并附带许可证与链接（以上游仓库/包管理页面为准）
        _buildAttributionRow(
          context: context,
          title: '框架',
          name: 'Flutter',
          url: 'https://github.com/flutter/flutter',
          description: '许可证：BSD-3-Clause（以 Flutter 仓库 LICENSE 为准）',
        ),
        _buildAttributionRow(
          context: context,
          title: '状态管理',
          name: 'Provider',
          url: 'https://pub.dev/packages/provider',
          description: '许可证：MIT（以 pub.dev 为准）',
        ),
        _buildAttributionRow(
          context: context,
          title: '动画支持',
          name: 'Lottie (lottie_flutter / lottie)',
          url: 'https://pub.dev/packages/lottie',
          description: '许可证：MIT（以 pub.dev 为准）',
        ),
        _buildAttributionRow(
          context: context,
          title: '本地存储',
          name: 'MMKV (本项目使用 Dart 适配)',
          url: 'https://github.com/Tencent/MMKV',
          description: '许可证：BSD-3-Clause（以腾讯官方仓库 LICENSE 为准），用于高性能键值存储与缓存',
        ),
        // 同步功能相关鸣谢
        const Text(
          '同步功能集成说明：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        _buildAttributionRow(
          context: context,
          title: '笔记同步',
          name: 'LocalSend（部分代码集成）',
          url: 'https://github.com/localsend/localsend',
          description:
              '同步功能参考并集成了 LocalSend 项目中的部分实现/代码片段。原项目许可证：MIT，已遵循并保留原始项目的许可证和作者信息，详情见上方链接。',
        ),
        const SizedBox(height: 12),
        const Text(
          '服务与 API 鸣谢：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildAttributionRow(
          context: context,
          title: '天气数据',
          name: 'Open-Meteo',
          url: 'https://open-meteo.com/',
          description: '提供气象与温度数据的免费 API，用于应用内天气功能。',
        ),
        _buildAttributionRow(
          context: context,
          title: '每日一言 API',
          name: 'Hitokoto (v1.hitokoto.cn)',
          url: 'https://hitokoto.cn/',
          description: '提供简短引言/一言数据，用于每日一言与笔记引用功能。',
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => _launchUrl(
            'https://flutter.dev/docs/development/packages-and-plugins/using-packages',
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('查看完整依赖列表'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '感谢所有开源项目与社区贡献者，正是这些工具和服务让本应用成为可能。具体许可证请以各项目仓库或包管理页面为准。',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12),
                  ),
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
    // 改为一个按钮，点击后跳转到单独的系统许可证页面（按需渲染，避免当前页面一次性构建大量条目）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '系统许可证包括 Flutter SDK 及依赖包的许可证，点击下方按钮查看完整列表。',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ProgressiveSystemLicensesPage()),
            );
          },
          icon: const Icon(Icons.article_outlined),
          label: const Text('查看系统许可证'),
          style:
              ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(Icons.animation_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    '来源: $creator',
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
      _licenseSub = LicenseRegistry.licenses.listen((entry) {
        _buffer.add(entry);
        // 启动或重置定时器：每 150ms 刷新一次到 UI
        _flushTimer ??= Timer.periodic(const Duration(milliseconds: 150), (_) {
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
      }, onError: (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _loading = false;
          });
        }
      }, onDone: () {
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
      });
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
    final visible = _filteredIndexes();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('系统许可证'),
            if (!_loading && _error.isEmpty)
              Text('${visible.length}/${_entries.length} 条',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '全部展开/折叠',
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
                const Icon(Icons.info_outline, color: Colors.blueGrey, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '本页自动汇总了 Flutter 及所有依赖包的许可证信息，内容由各依赖包声明自动生成，仅供参考。',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                hintText: '搜索包名或许可证内容（只搜索首段）',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
          ),
          Expanded(child: _buildBody(visible)),
        ],
      ),
    );
  }

  Widget _buildBody(List<int> visible) {
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
            Text('加载系统许可证失败：$_error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      );
    }
    if (_mergedEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 32),
            const SizedBox(height: 12),
            Text('未找到系统许可证条目', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text('未找到匹配的许可证条目', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            : '(无许可内容)';
        final initials =
            packages.isNotEmpty ? packages.trim()[0].toUpperCase() : 'P';
        final isExpanded = _expanded.contains(entryIndex);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              radius: 18,
              child: Text(initials,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            title: Text(packages.isEmpty ? '未命名' : packages,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              preview.length > 120
                  ? '${preview.substring(0, 120)}…'
                  : preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.9),
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
                    horizontal: 12.0, vertical: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: '复制许可证',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final paragraphs =
                            entry.paragraphs.map((p) => p.text).toList();
                        final full =
                            await compute(_joinParagraphs, paragraphs);
                        if (!mounted) return;
                        await Clipboard.setData(
                            ClipboardData(text: full));
                        if (!mounted) return;
                        messenger.showSnackBar(const SnackBar(
                            content: Text('已复制许可证内容'),
                            duration: Duration(seconds: 2)));
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: FutureBuilder<String>(
                  future: compute(_joinParagraphs,
                      entry.paragraphs.map((p) => p.text).toList()),
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
    LicenseRegistry.licenses.toList().then((list) {
      setState(() {
        _entries = list;
        _loading = false;
      });
    }).catchError((e) {
      setState(() {
        _entries = [];
        _error = e.toString();
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('系统许可证')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('加载系统许可证失败：$_error'));
    if (_entries.isEmpty) return const Center(child: Text('未找到系统许可证条目'));

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final packages = entry.packages.join(', ');
        final preview = entry.paragraphs.isNotEmpty
            ? entry.paragraphs.first.text
            : '(无许可内容)';
        final initials =
            packages.isNotEmpty ? packages.trim()[0].toUpperCase() : 'P';

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => LicenseDetailPage(
                      entry: entry,
                      title: packages.isEmpty ? '未命名' : packages)),
            );
          },
          child: Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    radius: 20,
                    child: Text(initials,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(packages.isEmpty ? '未命名' : packages,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                          preview.length > 140
                              ? '${preview.substring(0, 140)}…'
                              : preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.85)),
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
  const LicenseDetailPage({super.key, required this.entry, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: compute(_joinParagraphs, entry.paragraphs.map((p) => p.text).toList()),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text('加载许可证内容失败：${snapshot.error}'),
            );
          }
          final text = snapshot.data ?? '(无内容)';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(text, style: const TextStyle(height: 1.4)),
          );
        },
      ),
    );
  }
}
