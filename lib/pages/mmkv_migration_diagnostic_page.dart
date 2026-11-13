import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import '../services/app_preferences_service.dart';
import '../theme/app_semantic_colors.dart';
import '../theme/theme_style.dart';
import '../utils/app_logger.dart';
import '../utils/mmkv_binary_reader.dart';
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
  final AppPreferencesService? mmkvService;

  const MmkvMigrationDiagnosticPage({super.key, this.mmkvService});

  @override
  State<MmkvMigrationDiagnosticPage> createState() =>
      _MmkvMigrationDiagnosticPageState();
}

class _MmkvMigrationDiagnosticPageState
    extends State<MmkvMigrationDiagnosticPage> {
  late final AppPreferencesService _mmkvService;
  MmkvDiagnosticReport? _report;
  Object? _error;
  bool _loading = true;
  MmkvDiagnosticFilter _selectedFilter = MmkvDiagnosticFilter.all;

  @override
  void initState() {
    super.initState();
    _mmkvService = widget.mmkvService ?? AppPreferencesService();
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
    } catch (e, stackTrace) {
      logError(
        'MmkvMigrationDiagnosticPage: 生成诊断报告失败: $e',
        error: e,
        stackTrace: stackTrace,
      );
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
      final okMsg = _tr(
        isZh,
        '已重新执行三通道迁移并刷新校验结果',
        'Re-ran 3-channel migration and refreshed report',
      );
      AppSnackBar.success(context, okMsg);
    } catch (e, stackTrace) {
      logError(
        'MmkvMigrationDiagnosticPage: 重新执行迁移失败: $e',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      final errMsg = _tr(
        isZh,
        '重新执行迁移失败，请查看应用日志',
        'Migration failed, please check app logs',
      );
      AppSnackBar.error(context, errMsg);
    }
  }

  Future<void> _handleCopyJson() async {
    final report = _report;
    if (report == null) return;
    final isZh = _isChineseLocale(context);
    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(report.toRedactedJson());
    await Clipboard.setData(ClipboardData(text: jsonString));
    if (!mounted) return;
    final msg = _tr(
      isZh,
      '已复制脱敏诊断 JSON 到剪贴板',
      'Copied redacted diagnostic JSON to clipboard',
    );
    AppSnackBar.success(context, msg);
  }

  bool _isChineseLocale(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return locale == null || locale.languageCode.startsWith('zh');
  }

  String _tr(bool isZh, String zh, String en) {
    return isZh ? zh : en;
  }

  bool _isSpOnlyEntry(MmkvKeyComparisonEntry e) {
    if (!e.presentInSharedPrefs) return false;
    return !e.presentInBinary && !e.presentInNative;
  }

  bool _isStringEntry(MmkvKeyComparisonEntry e) {
    return e.valueType == 'String' || e.valueType == 'List<String>';
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
        return all.where(_isSpOnlyEntry).toList();
      case MmkvDiagnosticFilter.stringType:
        return all.where(_isStringEntry).toList();
      case MmkvDiagnosticFilter.boolType:
        return all.where((e) => e.valueType == 'bool').toList();
      case MmkvDiagnosticFilter.intType:
        return all.where((e) => e.valueType == 'int').toList();
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
      final errMsg = _tr(
        isZh,
        '生成诊断报告失败，请重试或查看应用日志',
        'Failed to generate diagnostic report, please retry',
      );
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
                errMsg,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadReport,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context).retry),
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

  String _formatCrcStatus(MmkvParseResult binary, bool isZh) {
    if (!binary.fileExists) {
      return isZh ? '无 mmkv.default 文件' : 'No mmkv.default file';
    }
    if (binary.crcMatched == true) {
      if (binary.usedLastConfirmed) {
        return isZh ? '通过 (回退至 lastConfirmed)' : 'Matched (via lastConfirmed)';
      }
      return isZh ? '通过 (CRC32 一致)' : 'Matched (CRC32 OK)';
    }
    if (binary.crcMatched == false) {
      return isZh ? 'CRC32 不匹配' : 'CRC32 Mismatch';
    }
    return isZh ? '无 .crc 伴随文件' : 'No .crc file';
  }

  String _formatMigratedStatus(bool migrated, bool isZh) {
    if (migrated) {
      return isZh ? '已完成 (true)' : 'Completed (true)';
    }
    return isZh ? '未标记 (false)' : 'Pending (false)';
  }

  String _formatNativeMirrorStatus(bool active, bool isZh) {
    if (active) {
      return isZh ? '已挂载 (双写与比对激活)' : 'Active (Dual-Write & Compare)';
    }
    return isZh ? '未挂载 (仅纯 Dart 解析 + SP)' : 'Inactive (Dart + SP)';
  }

  Widget _buildOverviewCard(
    BuildContext context,
    ThemeData theme,
    MmkvDiagnosticReport report,
    bool isZh,
  ) {
    final shapeTokens = AppShapeTokens.of(context);
    final btnRadius = BorderRadius.circular(shapeTokens.buttonRadius);
    final binary = report.primaryBinaryResult;
    final crcStatus = _formatCrcStatus(binary, isZh);
    final crcHex = binary.computedCrc32.toRadixString(16);
    final overviewTitle = _tr(
      isZh,
      '运行环境与二进制文件概览',
      'Environment & Binary File Overview',
    );
    final migratedText = _formatMigratedStatus(report.kvEngineMigrated, isZh);
    final mirrorText = _formatNativeMirrorStatus(
      report.nativeMmkvAvailable,
      isZh,
    );
    final String sizeText;
    if (binary.fileExists) {
      sizeText = '${binary.fileByteLength} B / ${binary.actualSize} B';
    } else {
      sizeText = isZh ? '文件不存在' : 'Not found';
    }
    final keyLen = binary.entries.length;
    final tombs = binary.tombstoneRecordsRead;
    final us = binary.parseDurationMicroseconds;
    final parseStats = '$us µs ($keyLen keys, $tombs tombstones)';

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
                    overviewTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            _buildInfoRow(
              theme,
              isZh ? '运行平台 / 位宽' : 'Platform / VM Bits',
              '${report.platformName} (${report.pointerBits}-bit)',
            ),
            _buildInfoRow(
              theme,
              isZh ? '迁移完成标志 (kv_engine_migrated_v1)' : 'Migration Flag',
              migratedText,
            ),
            _buildInfoRow(
              theme,
              isZh ? '原生 MMKV 镜像状态' : 'Native MMKV Mirror',
              mirrorText,
            ),
            _buildInfoRow(
              theme,
              isZh ? 'mmkv.default 路径' : 'mmkv.default Path',
              binary.filePath,
            ),
            _buildInfoRow(
              theme,
              isZh ? '文件大小 / actualSize' : 'File Size / actualSize',
              sizeText,
            ),
            _buildInfoRow(
              theme,
              isZh ? 'CRC32 校验状态' : 'CRC32 Status',
              '$crcStatus (0x$crcHex)',
            ),
            _buildInfoRow(
              theme,
              isZh ? '手写解析耗时 / 记录数' : 'Binary Parse Time / Records',
              parseStats,
            ),
            if (binary.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: btnRadius,
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
    final shapeTokens = AppShapeTokens.of(context);
    final btnRadius = BorderRadius.circular(shapeTokens.buttonRadius);
    final binaryKeyCount = report.primaryBinaryResult.entries.length;
    var nativeKeyCount = 0;
    var spKeyCount = 0;
    var binaryMatchedSpCount = 0;
    var binaryMatchNativeCount = 0;

    for (final c in report.comparisons) {
      if (c.presentInNative) nativeKeyCount++;
      if (c.presentInSharedPrefs) spKeyCount++;
      if (c.presentInBinary && c.binaryMatchesSharedPrefs) {
        binaryMatchedSpCount++;
      }
      if (c.presentInBinary && c.nativeMatchesBinary) {
        binaryMatchNativeCount++;
      }
    }

    final allClean = report.diffCount == 0;
    final Color badgeBg;
    final Color badgeFg;
    final Color iconColor;
    final String badgeText;

    if (allClean) {
      badgeBg = semantic.successContainer;
      badgeFg = semantic.onSuccessContainer;
      iconColor = theme.colorScheme.primary;
      final count = report.consistentCount;
      badgeText = isZh ? '100% 一致 ($count)' : '100% Match ($count)';
    } else {
      badgeBg = theme.colorScheme.errorContainer;
      badgeFg = theme.colorScheme.onErrorContainer;
      iconColor = theme.colorScheme.error;
      final diffs = report.diffCount;
      badgeText = isZh ? '发现 $diffs 项差异' : '$diffs Diff(s)';
    }

    final nativePart = report.nativeMmkvAvailable ? '$nativeKeyCount' : '-';
    final keyCountLabel = _tr(
      isZh,
      '存储源键总数 (Binary / Native / SP)',
      'Key Counts (Binary / Native / SP)',
    );
    final readerVsNativeLabel = _tr(
      isZh,
      '手写二进制解析 vs 原生 MMKV 匹配',
      'Dart Binary Reader vs Native MMKV',
    );
    final String readerVsNativeVal;
    if (report.nativeMmkvAvailable) {
      readerVsNativeVal = '$binaryMatchNativeCount / $binaryKeyCount';
    } else {
      readerVsNativeVal = isZh ? '原生未挂载 (以 SP 对照)' : 'N/A (Compared to SP)';
    }
    final spCoverageLabel = _tr(
      isZh,
      'SharedPreferences 迁移覆盖率',
      'SharedPreferences Migration Coverage',
    );

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
                  color: iconColor,
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
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: btnRadius,
                  ),
                  child: Text(
                    badgeText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: badgeFg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            _buildInfoRow(
              theme,
              keyCountLabel,
              '$binaryKeyCount / $nativePart / $spKeyCount',
            ),
            _buildInfoRow(
              theme,
              readerVsNativeLabel,
              readerVsNativeVal,
            ),
            _buildInfoRow(
              theme,
              spCoverageLabel,
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
          label:
              Text(AppLocalizations.of(context).mmkvDiagnosticRerunMigration),
        ),
        OutlinedButton.icon(
          key: const Key('mmkv_diagnostic_copy_json_action_button'),
          onPressed: (_loading || _report == null) ? null : _handleCopyJson,
          icon: const Icon(Icons.copy_all_outlined),
          label: Text(AppLocalizations.of(context).mmkvDiagnosticCopyJson),
        ),
      ],
    );
  }

  Widget _buildFilterChips(
    BuildContext context,
    MmkvDiagnosticReport report,
    bool isZh,
  ) {
    final total = report.comparisons.length;
    final diffs = report.diffCount;
    final allLabel = isZh ? '全部 ($total)' : 'All ($total)';
    final diffLabel = isZh ? '仅看差异 ($diffs)' : 'Diff Only ($diffs)';
    final spOnlyLabel = isZh ? '仅 SP' : 'SP Only';

    final filters = <(MmkvDiagnosticFilter, String)>[
      (MmkvDiagnosticFilter.all, allLabel),
      (MmkvDiagnosticFilter.diffOnly, diffLabel),
      (MmkvDiagnosticFilter.spOnly, spOnlyLabel),
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
    final shapeTokens = AppShapeTokens.of(context);
    final btnRadius = BorderRadius.circular(shapeTokens.buttonRadius);
    final spOnly = _isSpOnlyEntry(entry);

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
    final absentText = isZh ? '<不存在>' : '<absent>';
    final binaryPreview = _previewOrAbsent(
      entry.presentInBinary,
      redactedMap['binaryValue'],
      absentText,
    );
    final nativePreview = _previewOrAbsent(
      entry.presentInNative,
      redactedMap['nativeValue'],
      absentText,
    );
    final spPreview = _previewOrAbsent(
      entry.presentInSharedPrefs,
      redactedMap['sharedPrefsValue'],
      absentText,
    );

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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: btnRadius,
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
          _buildValuePreviewRow(theme, 'Dart Binary Reader', binaryPreview),
          if (nativeAvailable)
            _buildValuePreviewRow(theme, 'Native MMKV', nativePreview),
          _buildValuePreviewRow(theme, 'SharedPreferences', spPreview),
        ],
      ),
    );
  }

  String _previewOrAbsent(bool present, Object? raw, String absentText) {
    return present ? _formatPreviewValue(raw) : absentText;
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
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
      padding: const EdgeInsets.only(top: 8.0),
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
