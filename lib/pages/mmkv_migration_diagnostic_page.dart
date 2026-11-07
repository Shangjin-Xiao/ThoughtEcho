import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import '../services/mmkv_service.dart';
import '../theme/app_semantic_colors.dart';
import '../utils/mmkv_ffi_fix.dart';
import '../widgets/app_snackbar.dart';

/// Filter modes for the key-by-key inspector in [MmkvMigrationDiagnosticPage].
enum MmkvDiagnosticFilter {
  all,
  diffOnly,
  spOnly,
  stringType,
  boolType,
  intType,
}

/// Developer Settings page for inspecting the MMKV -> SharedPreferences
/// migration status and verifying 1:1 parity between Native MMKV, the pure-Dart
/// `MmkvBinaryReader`, and `SharedPreferences`.
class MmkvMigrationDiagnosticPage extends StatefulWidget {
  final MMKVService? mmkvService;

  const MmkvMigrationDiagnosticPage({super.key, this.mmkvService});

  @override
  State<MmkvMigrationDiagnosticPage> createState() =>
      _MmkvMigrationDiagnosticPageState();
}

class _MmkvMigrationDiagnosticPageState
    extends State<MmkvMigrationDiagnosticPage> {
  late final MMKVService _mmkvService;
  MmkvDiagnosticReport? _report;
  Object? _error;
  bool _loading = true;
  MmkvDiagnosticFilter _selectedFilter = MmkvDiagnosticFilter.all;

  @override
  void initState() {
    super.initState();
    _mmkvService = widget.mmkvService ?? MMKVService();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await _mmkvService.collectDiagnosticReport();
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _handleRerunMigration() async {
    final isZh = _isChineseLocale(context);
    setState(() {
      _loading = true;
    });
    try {
      await _mmkvService.runMigration(force: true);
      final report = await _mmkvService.collectDiagnosticReport();
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
      AppSnackBar.success(
        context,
        isZh
            ? '已重新执行三通道迁移并刷新校验结果'
            : 'Re-ran 3-channel migration and refreshed report',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      AppSnackBar.error(
        context,
        isZh ? '重新执行迁移失败: $e' : 'Migration failed: $e',
      );
    }
  }

  Future<void> _handleCopyJson() async {
    final report = _report;
    if (report == null) return;
    final isZh = _isChineseLocale(context);
    final jsonString =
        const JsonEncoder.withIndent('  ').convert(report.toRedactedJson());
    await Clipboard.setData(ClipboardData(text: jsonString));
    if (!mounted) return;
    AppSnackBar.success(
      context,
      isZh
          ? '已复制脱敏诊断 JSON 到剪贴板'
          : 'Copied redacted diagnostic JSON to clipboard',
    );
  }

  bool _isChineseLocale(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return locale == null || locale.languageCode.startsWith('zh');
  }

  List<MmkvKeyComparisonEntry> _filteredEntries(
    List<MmkvKeyComparisonEntry> all,
  ) {
    switch (_selectedFilter) {
      case MmkvDiagnosticFilter.all:
        return all;
      case MmkvDiagnosticFilter.diffOnly:
        return all.where((e) => !e.allConsistent).toList();
      case MmkvDiagnosticFilter.spOnly:
        return all
            .where(
              (e) =>
                  e.presentInSharedPrefs &&
                  !e.presentInBinary &&
                  !e.presentInNative,
            )
            .toList();
      case MmkvDiagnosticFilter.stringType:
        return all
            .where(
              (e) => e.valueType == 'String' || e.valueType == 'List<String>',
            )
            .toList();
      case MmkvDiagnosticFilter.boolType:
        return all.where((e) => e.valueType == 'bool').toList();
      case MmkvDiagnosticFilter.intType:
        return all
            .where((e) => e.valueType == 'int' || e.valueType == 'double')
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isZh = _isChineseLocale(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mmkvDiagnosticTitle),
        actions: [
          IconButton(
            key: const Key('mmkv_diagnostic_rescan_button'),
            tooltip: isZh ? '重新扫描对比' : 'Rescan & Compare',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadReport,
          ),
          IconButton(
            key: const Key('mmkv_diagnostic_copy_button'),
            tooltip: isZh ? '复制脱敏诊断 JSON' : 'Copy Redacted JSON',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: (_loading || _report == null) ? null : _handleCopyJson,
          ),
        ],
      ),
      body: _buildBody(context, theme, isZh),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, bool isZh) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                isZh
                    ? '生成诊断报告失败：$_error'
                    : 'Failed to generate diagnostic report: $_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadReport,
                icon: const Icon(Icons.refresh),
                label: Text(isZh ? '重试' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final report = _report!;
    final filtered = _filteredEntries(report.comparisons);

    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        _buildOverviewCard(context, theme, report, isZh),
        const SizedBox(height: 8),
        _buildConsistencySummaryCard(context, theme, report, isZh),
        const SizedBox(height: 8),
        _buildActionRow(context, isZh),
        const SizedBox(height: 12),
        _buildFilterChips(context, report, isZh),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  isZh ? '当前筛选条件下无匹配键' : 'No keys match current filter',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
        else
          ...filtered.map(
            (entry) => _buildKeyComparisonTile(
              context,
              theme,
              entry,
              report.nativeMmkvAvailable,
              isZh,
            ),
          ),
      ],
    );
  }

  Widget _buildOverviewCard(
    BuildContext context,
    ThemeData theme,
    MmkvDiagnosticReport report,
    bool isZh,
  ) {
    final binary = report.primaryBinaryResult;
    final crcStatus = !binary.fileExists
        ? (isZh ? '无 mmkv.default 文件' : 'No mmkv.default file')
        : binary.crcMatched == true
            ? (binary.usedLastConfirmed
                ? (isZh
                    ? '通过 (回退至 lastConfirmed)'
                    : 'Matched (via lastConfirmed)')
                : (isZh ? '通过 (CRC32 一致)' : 'Matched (CRC32 OK)'))
            : binary.crcMatched == false
                ? (isZh ? 'CRC32 不匹配' : 'CRC32 Mismatch')
                : (isZh ? '无 .crc 伴随文件' : 'No .crc file');

    return Card(
      key: const Key('mmkv_diagnostic_overview_card'),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh ? '运行环境与二进制文件概览' : 'Environment & Binary File Overview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildInfoRow(
              theme,
              isZh ? '运行平台 / 位宽' : 'Platform / VM Bits',
              '${report.platformName} (${report.pointerBits}-bit)',
            ),
            _buildInfoRow(
              theme,
              isZh ? '迁移完成标志 (kv_engine_migrated_v1)' : 'Migration Flag',
              report.kvEngineMigrated
                  ? (isZh ? '已完成 (true)' : 'Completed (true)')
                  : (isZh ? '未标记 (false)' : 'Pending (false)'),
            ),
            _buildInfoRow(
              theme,
              isZh ? '原生 MMKV 镜像状态' : 'Native MMKV Mirror',
              report.nativeMmkvAvailable
                  ? (isZh ? '已挂载 (双写与比对激活)' : 'Active (Dual-Write & Compare)')
                  : (isZh ? '未挂载 (仅纯 Dart 解析 + SP)' : 'Inactive (Dart + SP)'),
            ),
            _buildInfoRow(
              theme,
              isZh ? 'mmkv.default 路径' : 'mmkv.default Path',
              binary.filePath,
            ),
            _buildInfoRow(
              theme,
              isZh ? '文件大小 / actualSize' : 'File Size / actualSize',
              binary.fileExists
                  ? '${binary.fileByteLength} B / ${binary.actualSize} B'
                  : (isZh ? '文件不存在' : 'Not found'),
            ),
            _buildInfoRow(
              theme,
              isZh ? 'CRC32 校验状态' : 'CRC32 Status',
              '$crcStatus (0x${binary.computedCrc32.toRadixString(16)})',
            ),
            _buildInfoRow(
              theme,
              isZh ? '手写解析耗时 / 记录数' : 'Binary Parse Time / Records',
              '${binary.parseDurationMicroseconds} µs '
              '(${binary.entries.length} keys, ${binary.tombstoneRecordsRead} tombstones)',
            ),
            if (binary.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  binary.warnings.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConsistencySummaryCard(
    BuildContext context,
    ThemeData theme,
    MmkvDiagnosticReport report,
    bool isZh,
  ) {
    final semantic = AppSemanticColors.of(context);
    final binaryKeyCount = report.primaryBinaryResult.entries.length;
    final nativeKeyCount =
        report.comparisons.where((c) => c.presentInNative).length;
    final spKeyCount =
        report.comparisons.where((c) => c.presentInSharedPrefs).length;
    final binaryMatchedSpCount = report.comparisons
        .where((c) => c.presentInBinary && c.binaryMatchesSharedPrefs)
        .length;
    final binaryMatchNativeCount = report.comparisons
        .where((c) => c.presentInBinary && c.nativeMatchesBinary)
        .length;

    final allClean = report.diffCount == 0;
    final badgeBg =
        allClean ? semantic.successContainer : theme.colorScheme.errorContainer;
    final badgeFg = allClean
        ? semantic.onSuccessContainer
        : theme.colorScheme.onErrorContainer;

    return Card(
      key: const Key('mmkv_diagnostic_summary_card'),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allClean ? Icons.verified_outlined : Icons.warning_amber,
                  color: allClean
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh ? '三方一致性比对大盘' : '3-Way Consistency Summary',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    allClean
                        ? (isZh
                            ? '100% 一致 (${report.consistentCount})'
                            : '100% Match (${report.consistentCount})')
                        : (isZh
                            ? '发现 ${report.diffCount} 项差异'
                            : '${report.diffCount} Diff(s)'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: badgeFg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildInfoRow(
              theme,
              isZh ? '存储源键总数 (Binary / Native / SP)' : 'Key Counts (Binary / Native / SP)',
              '$binaryKeyCount / ${report.nativeMmkvAvailable ? nativeKeyCount : '-'} / $spKeyCount',
            ),
            _buildInfoRow(
              theme,
              isZh
                  ? '手写二进制解析 vs 原生 MMKV 匹配'
                  : 'Dart Binary Reader vs Native MMKV',
              report.nativeMmkvAvailable
                  ? '$binaryMatchNativeCount / $binaryKeyCount'
                  : (isZh ? '原生未挂载 (以 SP 对照)' : 'N/A (Compared against SP)'),
            ),
            _buildInfoRow(
              theme,
              isZh
                  ? 'SharedPreferences 迁移覆盖率'
                  : 'SharedPreferences Migration Coverage',
              '$binaryMatchedSpCount / $binaryKeyCount',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, bool isZh) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          key: const Key('mmkv_diagnostic_rerun_migration_button'),
          onPressed: _loading ? null : _handleRerunMigration,
          icon: const Icon(Icons.sync),
          label: Text(isZh ? '重新执行迁移' : 'Re-run Migration'),
        ),
        OutlinedButton.icon(
          key: const Key('mmkv_diagnostic_copy_json_action_button'),
          onPressed: (_loading || _report == null) ? null : _handleCopyJson,
          icon: const Icon(Icons.copy_all_outlined),
          label: Text(isZh ? '复制诊断 JSON' : 'Copy Diagnostic JSON'),
        ),
      ],
    );
  }

  Widget _buildFilterChips(
    BuildContext context,
    MmkvDiagnosticReport report,
    bool isZh,
  ) {
    final filters = <(MmkvDiagnosticFilter, String)>[
      (
        MmkvDiagnosticFilter.all,
        isZh
            ? '全部 (${report.comparisons.length})'
            : 'All (${report.comparisons.length})',
      ),
      (
        MmkvDiagnosticFilter.diffOnly,
        isZh
            ? '仅看差异 (${report.diffCount})'
            : 'Diff Only (${report.diffCount})',
      ),
      (
        MmkvDiagnosticFilter.spOnly,
        isZh ? '仅 SP' : 'SP Only',
      ),
      (MmkvDiagnosticFilter.stringType, 'String'),
      (MmkvDiagnosticFilter.boolType, 'Bool'),
      (MmkvDiagnosticFilter.intType, 'Int'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((item) {
          final selected = _selectedFilter == item.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              key: Key('mmkv_filter_${item.$1.name}'),
              selected: selected,
              label: Text(item.$2),
              onSelected: (_) {
                setState(() {
                  _selectedFilter = item.$1;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKeyComparisonTile(
    BuildContext context,
    ThemeData theme,
    MmkvKeyComparisonEntry entry,
    bool nativeAvailable,
    bool isZh,
  ) {
    final semantic = AppSemanticColors.of(context);
    final spOnly = entry.presentInSharedPrefs &&
        !entry.presentInBinary &&
        !entry.presentInNative;

    final String statusLabel;
    final Color statusBg;
    final Color statusFg;

    if (!entry.allConsistent) {
      statusLabel = isZh ? '差异' : 'Diff';
      statusBg = theme.colorScheme.errorContainer;
      statusFg = theme.colorScheme.onErrorContainer;
    } else if (spOnly) {
      statusLabel = isZh ? '仅 SP' : 'SP Only';
      statusBg = theme.colorScheme.secondaryContainer;
      statusFg = theme.colorScheme.onSecondaryContainer;
    } else {
      statusLabel = isZh ? '一致' : 'Match';
      statusBg = semantic.successContainer;
      statusFg = semantic.onSuccessContainer;
    }

    final redactedMap = entry.toRedactedJson();

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ExpansionTile(
        key: Key('mmkv_key_tile_${entry.key}'),
        title: Text(
          entry.key,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Type: ${entry.valueType}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            statusLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: statusFg,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _buildValuePreviewRow(
            theme,
            'Dart Binary Reader',
            entry.presentInBinary
                ? _formatPreviewValue(redactedMap['binaryValue'])
                : (isZh ? '<不存在>' : '<absent>'),
          ),
          if (nativeAvailable)
            _buildValuePreviewRow(
              theme,
              'Native MMKV',
              entry.presentInNative
                  ? _formatPreviewValue(redactedMap['nativeValue'])
                  : (isZh ? '<不存在>' : '<absent>'),
            ),
          _buildValuePreviewRow(
            theme,
            'SharedPreferences',
            entry.presentInSharedPrefs
                ? _formatPreviewValue(redactedMap['sharedPrefsValue'])
                : (isZh ? '<不存在>' : '<absent>'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValuePreviewRow(ThemeData theme, String source, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              source,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPreviewValue(Object? value) {
    if (value == null) return 'null';
    final text = value is List ? json.encode(value) : value.toString();
    if (text.length > 260) {
      return '${text.substring(0, 260)}... (${text.length} chars)';
    }
    return text;
  }
}
