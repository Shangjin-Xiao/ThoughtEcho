import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/mmkv_service.dart';
import '../services/webdav_sync_service.dart';
import '../utils/lww_utils.dart';
import '../utils/app_logger.dart';

class WebDAVSyncPage extends StatefulWidget {
  const WebDAVSyncPage({super.key});

  @override
  State<WebDAVSyncPage> createState() => _WebDAVSyncPageState();
}

class _WebDAVSyncPageState extends State<WebDAVSyncPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _urlController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;

  String _selectedProvider = 'custom';
  bool _obscurePassword = true;
  bool _isTestingConnection = false;
  bool _hasConflicts = false;
  int _conflictNotesCount = 0;

  @override
  void initState() {
    super.initState();
    final syncService = Provider.of<WebDAVSyncService>(context, listen: false);

    _selectedProvider = syncService.provider;
    _urlController = TextEditingController(text: syncService.url);
    _usernameController = TextEditingController(text: syncService.username);
    _passwordController = TextEditingController(); // 密码仅在保存时输入或读取

    _loadSecurePassword();
    _checkConflictNotes();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showExperimentalWarningIfNeeded();
    });
  }

  /// 弹出实验性功能预览提示（符合国际化，支持临时关闭或永久忽略）
  Future<void> _showExperimentalWarningIfNeeded() async {
    final mmkv = MMKVService();
    final ignoreWarning =
        mmkv.getBool('webdav_ignore_experimental_warning') ?? false;
    if (ignoreWarning) return;

    if (!mounted) return;

    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      barrierDismissible: false, // 强制用户阅读并交互
      builder: (BuildContext context) {
        return AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber,
            size: 40,
          ),
          title: Text(l10n.webdavExperimentalTitle),
          content: Text(
            l10n.webdavExperimentalContent,
            style: const TextStyle(height: 1.5),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () async {
                final mmkv = MMKVService();
                await mmkv.setBool('webdav_ignore_experimental_warning', true);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: Text(
                l10n.webdavExperimentalIgnore,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(l10n.webdavExperimentalClose),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadSecurePassword() async {
    final password =
        await Provider.of<WebDAVSyncService>(context, listen: false)
            .getPassword();
    if (password != null && mounted) {
      setState(() {
        _passwordController.text = password;
      });
    }
  }

  /// 检查是否有冲突笔记，用于动态显示“查看冲突”按钮
  Future<void> _checkConflictNotes() async {
    try {
      final db = DatabaseService().database;
      final result = await db.query(
        'quotes',
        columns: ['id'],
        where: 'category_id = ? AND is_deleted = 0',
        whereArgs: [WebDAVSyncService.conflictCategoryId],
      );
      if (mounted) {
        setState(() {
          _conflictNotesCount = result.length;
          _hasConflicts = result.isNotEmpty;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.e(
        '检查冲突笔记失败',
        error: e,
        stackTrace: stackTrace,
        source: 'WebDAVSyncPage',
      );
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 预设云盘地址自动填入
  void _onProviderChanged(String? provider) {
    if (provider == null) return;
    setState(() {
      _selectedProvider = provider;
      if (provider == 'nutstore') {
        _urlController.text = 'https://dav.jianguoyun.com/dav/';
      } else if (provider == 'infinicloud') {
        _urlController.text = 'https://dav.teracloud.jp/dav/';
      } else if (provider == 'nextcloud') {
        if (_urlController.text == 'https://dav.jianguoyun.com/dav/' ||
            _urlController.text == 'https://dav.teracloud.jp/dav/') {
          _urlController.text = '';
        }
      } else {
        // 自定义保持原有内容
      }
    });
  }

  /// 打开第三方应用密码的帮助指南链接
  Future<void> _launchHelpGuide() async {
    final l10n = AppLocalizations.of(context);
    Uri url;
    if (_selectedProvider == 'nutstore') {
      url = Uri.parse('https://help.jianguoyun.com/?p=2064');
    } else if (_selectedProvider == 'infinicloud') {
      url = Uri.parse('https://infinicloud.com/en/support.html');
    } else {
      url = Uri.parse(
          'https://google.com/search?q=how+to+setup+webdav+app+password');
    }

    try {
      final launched = await launchUrl(url, mode: LaunchMode.platformDefault);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.webdavOpenHelpFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.webdavOpenHelpFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 测试连接
  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTestingConnection = true;
    });

    final l10n = AppLocalizations.of(context);
    final syncService = Provider.of<WebDAVSyncService>(context, listen: false);

    final success = await syncService.testConnection(
      _urlController.text,
      _usernameController.text,
      _passwordController.text,
    );

    setState(() {
      _isTestingConnection = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? l10n.webdavTestSuccess : l10n.webdavTestFailed),
          backgroundColor:
              success ? Colors.green.shade600 : Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 保存配置并触发首次同步
  Future<void> _saveAndSync(WebDAVSyncService syncService) async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);

    // 1. 保存设置
    await syncService.saveSettings(
      enabled: true,
      provider: _selectedProvider,
      url: _urlController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      syncOnLaunch: syncService.syncOnLaunch,
      syncOnChange: syncService.syncOnChange,
      syncOnCellular: syncService.syncOnCellular,
      syncNotesOnlyOnCellular: syncService.syncNotesOnlyOnCellular,
    );

    // 2. 触发一次手动同步
    await _triggerManualSync(syncService, l10n);
  }

  /// 触发手动同步
  Future<void> _triggerManualSync(
      WebDAVSyncService syncService, AppLocalizations l10n) async {
    await syncService.triggerSync();
    await _checkConflictNotes();

    if (mounted) {
      if (syncService.syncStatus == WebDAVSyncStatus.success) {
        // 如果同步产生冲突，弹出包含 [查看] 按钮的 SnackBar
        if (syncService.lastConflictCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n
                  .webdavConflictNotification(syncService.lastConflictCount)),
              backgroundColor: Colors.amber.shade800,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: l10n.webdavViewNow,
                textColor: Colors.white,
                onPressed: _navigateToConflicts,
              ),
              duration: const Duration(seconds: 8),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.webdavStatusSuccess),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (syncService.syncStatus == WebDAVSyncStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.webdavStatusFailed),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 导航到冲突笔记列表（以分类过滤的独立页面展示）
  void _navigateToConflicts() {
    final l10n = AppLocalizations.of(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(l10n.webdavConflictCategoryName),
            elevation: 0,
          ),
          body: QuoteListViewByConflict(),
        ),
      ),
    ).then((_) => _checkConflictNotes());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.webdavSyncTitle),
        elevation: 0,
      ),
      body: Consumer<WebDAVSyncService>(
        builder: (context, syncService, _) {
          return SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- 云端同步状态总览 Card ---
                  _buildStatusCard(syncService, l10n, theme),
                  const SizedBox(height: 24),

                  // --- 账号配置表单 Section ---
                  Text(
                    '服务商配置',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // 1. 服务商下拉选择
                          DropdownButtonFormField<String>(
                            initialValue: _selectedProvider,
                            decoration: InputDecoration(
                              labelText: l10n.webdavProvider,
                              prefixIcon: const Icon(Icons.cloud_outlined),
                            ),
                            items: [
                              DropdownMenuItem(
                                  value: 'nutstore',
                                  child: Text(l10n.webdavProviderNutstore)),
                              DropdownMenuItem(
                                  value: 'nextcloud',
                                  child: Text(l10n.webdavProviderNextcloud)),
                              DropdownMenuItem(
                                  value: 'infinicloud',
                                  child: Text(l10n.webdavProviderInfinicloud)),
                              DropdownMenuItem(
                                  value: 'custom',
                                  child: Text(l10n.webdavProviderCustom)),
                            ],
                            onChanged: _onProviderChanged,
                          ),
                          const SizedBox(height: 16),

                          // 2. 服务器 URL
                          TextFormField(
                            controller: _urlController,
                            enabled: _selectedProvider == 'custom' ||
                                _selectedProvider == 'nextcloud',
                            decoration: InputDecoration(
                              labelText: l10n.webdavServerUrl,
                              prefixIcon: const Icon(Icons.link),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return '请输入 WebDAV 服务器地址';
                              }
                              if (!val.trim().startsWith('http://') &&
                                  !val.trim().startsWith('https://')) {
                                return '地址必须以 http:// 或 https:// 开头';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // 3. 用户名
                          TextFormField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: l10n.webdavUsername,
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            validator: (val) =>
                                (val == null || val.trim().isEmpty)
                                    ? '请输入用户名'
                                    : null,
                          ),
                          const SizedBox(height: 16),

                          // 4. 密码/Token
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: l10n.webdavPassword,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (val) =>
                                (val == null || val.isEmpty) ? '请输入应用密码' : null,
                          ),

                          // 引导链接文字
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _launchHelpGuide,
                              icon: const Icon(Icons.help_outline, size: 16),
                              label: Text(
                                l10n.webdavHowToGetAppPassword,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- 自动同步策略 Switch ---
                  Text(
                    '同步策略',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text(l10n.webdavAutoSyncLaunch),
                          subtitle: Text(l10n.webdavAutoSyncLaunchSubtitle),
                          value: syncService.syncOnLaunch,
                          onChanged: (val) {
                            syncService.saveSettings(
                              enabled: syncService.enabled,
                              provider: _selectedProvider,
                              url: _urlController.text,
                              username: _usernameController.text,
                              syncOnLaunch: val,
                              syncOnChange: syncService.syncOnChange,
                              syncOnCellular: syncService.syncOnCellular,
                              syncNotesOnlyOnCellular:
                                  syncService.syncNotesOnlyOnCellular,
                            );
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: Text(l10n.webdavAutoSyncChange),
                          subtitle: Text(l10n.webdavAutoSyncChangeSubtitle),
                          value: syncService.syncOnChange,
                          onChanged: (val) {
                            syncService.saveSettings(
                              enabled: syncService.enabled,
                              provider: _selectedProvider,
                              url: _urlController.text,
                              username: _usernameController.text,
                              syncOnLaunch: syncService.syncOnLaunch,
                              syncOnChange: val,
                              syncOnCellular: syncService.syncOnCellular,
                              syncNotesOnlyOnCellular:
                                  syncService.syncNotesOnlyOnCellular,
                            );
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: Text(l10n.webdavSyncOnCellular),
                          subtitle: Text(l10n.webdavSyncOnCellularSubtitle),
                          value: syncService.syncOnCellular,
                          onChanged: (val) {
                            syncService.saveSettings(
                              enabled: syncService.enabled,
                              provider: _selectedProvider,
                              url: _urlController.text,
                              username: _usernameController.text,
                              syncOnLaunch: syncService.syncOnLaunch,
                              syncOnChange: syncService.syncOnChange,
                              syncOnCellular: val,
                              syncNotesOnlyOnCellular:
                                  syncService.syncNotesOnlyOnCellular,
                            );
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: Text(l10n.webdavSyncNotesOnlyOnCellular),
                          subtitle:
                              Text(l10n.webdavSyncNotesOnlyOnCellularSubtitle),
                          value: syncService.syncNotesOnlyOnCellular,
                          onChanged: syncService.syncOnCellular
                              ? null
                              : (val) {
                                  syncService.saveSettings(
                                    enabled: syncService.enabled,
                                    provider: _selectedProvider,
                                    url: _urlController.text,
                                    username: _usernameController.text,
                                    syncOnLaunch: syncService.syncOnLaunch,
                                    syncOnChange: syncService.syncOnChange,
                                    syncOnCellular: syncService.syncOnCellular,
                                    syncNotesOnlyOnCellular: val,
                                  );
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- 操作按钮板 Section ---
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _isTestingConnection ? null : _testConnection,
                          icon: _isTestingConnection
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.wifi_tethering),
                          label: Text(l10n.webdavTestConnection),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: syncService.isSyncing
                              ? null
                              : () => _saveAndSync(syncService),
                          icon: syncService.isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Icon(
                                  syncService.enabled
                                      ? Icons.save_outlined
                                      : Icons.cloud_sync_outlined,
                                ),
                          label: Text(syncService.enabled
                              ? l10n.webdavSaveAndSync
                              : l10n.webdavEnableSync),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 禁用云同步按钮（仅在已启用状态下显示）
                  if (syncService.enabled) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        syncService.saveSettings(
                          enabled: false,
                          provider: _selectedProvider,
                          url: _urlController.text,
                          username: _usernameController.text,
                          syncOnLaunch: syncService.syncOnLaunch,
                          syncOnChange: syncService.syncOnChange,
                          syncOnCellular: syncService.syncOnCellular,
                          syncNotesOnlyOnCellular:
                              syncService.syncNotesOnlyOnCellular,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.webdavDisableSyncSuccess),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.cloud_off, color: Colors.red),
                      label: Text(l10n.webdavDisableSync,
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建状态预览卡片
  Widget _buildStatusCard(
      WebDAVSyncService syncService, AppLocalizations l10n, ThemeData theme) {
    String stateTitle = '未启用云同步';
    String stateDesc = '配置您的 WebDAV 服务，享受安全跨端多路同步。';
    IconData stateIcon = Icons.cloud_off_outlined;
    Color accentColor = theme.colorScheme.outline;

    if (syncService.enabled) {
      if (syncService.isSyncing) {
        stateTitle = l10n.webdavStatusSyncing;
        stateDesc = '正在安全比对合并云端与本地数据库文件...';
        stateIcon = Icons.sync;
        accentColor = theme.colorScheme.primary;
      } else if (syncService.syncStatus == WebDAVSyncStatus.success) {
        stateTitle = '云同步运行中';
        final relativeTime = syncService.lastSyncTime.isNotEmpty
            ? LWWUtils.formatTimestamp(syncService.lastSyncTime)
            : '从未成功';
        stateDesc = '已与云端网盘建立加密合并管道。\n上次同步：$relativeTime';
        stateIcon = Icons.cloud_done;
        accentColor = Colors.green.shade600;
      } else if (syncService.syncStatus == WebDAVSyncStatus.failed) {
        stateTitle = '同步出现异常';
        stateDesc = '网络通信或云盘文件锁冲突。我们将自动重试。';
        stateIcon = Icons.error_outline;
        accentColor = theme.colorScheme.error;
      } else {
        stateTitle = '云同步已启用';
        final relativeTime = syncService.lastSyncTime.isNotEmpty
            ? LWWUtils.formatTimestamp(syncService.lastSyncTime)
            : '从未同步';
        stateDesc = '服务就绪。上次同步：$relativeTime';
        stateIcon = Icons.cloud_queue;
        accentColor = theme.colorScheme.secondary;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: accentColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              accentColor.withValues(alpha: 0.05),
              accentColor.withValues(alpha: 0.12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: syncService.isSyncing
                      ? SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(stateIcon, size: 28, color: accentColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stateTitle,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stateDesc,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 同步失败时显示错误摘要（位于冲突区块之前）
            if (syncService.syncStatus == WebDAVSyncStatus.failed &&
                syncService.lastSyncError.isNotEmpty) ...[
              const Divider(height: 24, thickness: 0.8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onErrorContainer,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncService.lastSyncError,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 如果存在同步冲突，提供专属查看操作区
            if (_hasConflicts) ...[
              const Divider(height: 24, thickness: 0.8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade500.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '检测到有 $_conflictNotesCount 篇同步冲突备份，建议立即处理。',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: Colors.amber.shade900),
                      ),
                    ),
                    TextButton(
                      onPressed: _navigateToConflicts,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(l10n.webdavGoToResolve,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                  ],
                ),
              ),
            ],

            // 立即同步按钮（仅在启用后且不在同步中时提供）
            if (syncService.enabled && !syncService.isSyncing) ...[
              const Divider(height: 24, thickness: 0.8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _triggerManualSync(syncService, l10n),
                  icon: const Icon(Icons.sync_outlined),
                  label: Text(l10n.webdavSyncNow),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 冲突笔记专属查看过滤列表 (以系统特定分类 ID 过滤)
class QuoteListViewByConflict extends StatelessWidget {
  const QuoteListViewByConflict({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();
    final theme = Theme.of(context);

    return StreamBuilder<List<Quote>>(
      stream: dbService.watchQuotes(
        categoryId: WebDAVSyncService.conflictCategoryId,
        includeDeleted: false,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final quotes = snapshot.data ?? [];
        if (quotes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 64, color: Colors.green.shade500),
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context).webdavNoConflicts,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(AppLocalizations.of(context).webdavAllConflictsResolved,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: quotes.length,
          padding: const EdgeInsets.all(16),
          itemBuilder: (context, index) {
            final quote = quotes[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(
                  quote.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        LWWUtils.formatTimestamp(quote.lastModified),
                        style: TextStyle(
                            fontSize: 12, color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 一键恢复/移动：改分类至默认，使其移出冲突
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: AppLocalizations.of(context)
                          .webdavConflictKeepTooltip,
                      onPressed: () async {
                        // 更新分类为默认（空）
                        final updated = quote.copyWith(
                          categoryId: '',
                          content: quote.content.replaceFirst('[冲突备份] ', ''),
                          lastModified:
                              DateTime.now().toUtc().toIso8601String(),
                        );
                        await dbService.updateQuote(updated);
                        dbService.refreshQuotes();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context)
                                  .webdavConflictKeepSuccess),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                    // 一键丢弃/删除
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: AppLocalizations.of(context)
                          .webdavConflictDiscardTooltip,
                      onPressed: () async {
                        // 永久删除该笔记
                        await dbService.permanentlyDeleteQuote(quote.id!);
                        dbService.refreshQuotes();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context)
                                  .webdavConflictDiscardSuccess),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
