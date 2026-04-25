part of '../main.dart';

/// 紧急恢复页面,在数据库初始化失败时显示
class EmergencyRecoveryPage extends StatelessWidget {
  const EmergencyRecoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.emergencyRecoveryTitle),
        backgroundColor: Colors.red,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // 添加SingleChildScrollView使内容可滚动
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, // 设置为min以适应内容
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.emergencyRecoveryHeading,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.emergencyRecoveryDescription,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () async {
                    // 标记为 async
                    // 导航前检查 mounted 状态
                    if (!context.mounted) return;
                    await Navigator.push(
                      // 使用 await
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BackupRestorePage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.backup),
                  label: Text(l10n.emergencyBackupAndRestoreButton),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    // 尝试重新初始化数据库
                    try {
                      final databaseService = DatabaseService();
                      databaseService.reinitialize();
                      await databaseService.initializeNewDatabase();

                      if (!context.mounted) return;

                      // 成功后导航到主页
                      await Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HomePage(),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;

                      // 如果重新初始化失败,显示错误信息
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.emergencyReinitializeFailed('$e')),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.emergencyTryRestartAppButton),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  l10n.emergencyRecoveryHint,
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 极端情况下的应急应用,当初始化完全失败时启动
class EmergencyApp extends StatelessWidget {
  final String error;
  final String stackTrace;

  const EmergencyApp({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThoughtEcho Emergency',
      navigatorKey: navigatorKey, // 使用全局导航键
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(boldText: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.light,
        ),
      ),
      home: EmergencyHomePage(error: error, stackTrace: stackTrace),
      routes: {'/backup_restore': (context) => const BackupRestorePage()},
    );
  }
}

/// 紧急模式下的主页面
class EmergencyHomePage extends StatelessWidget {
  final String error;
  final String stackTrace;

  const EmergencyHomePage({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    // 防御性处理:国际化可能尚未初始化完成,使用 nullable 版本
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final emergencyModeTitle = l10n?.emergencyModeTitle ?? 'Emergency Mode';
    final emergencyAppStartFailedTitle =
        l10n?.emergencyAppStartFailedTitle ?? 'App Start Failed';
    final emergencyAppStartFailedDesc = l10n?.emergencyAppStartFailedDesc ??
        'The app failed to start properly. Please try the recovery options below.';
    final emergencyErrorLabel = l10n?.emergencyErrorLabel ?? 'Error:';
    final emergencyTechnicalDetails =
        l10n?.emergencyTechnicalDetails ?? 'Technical Details';
    final emergencyBackupAndRestoreButton =
        l10n?.emergencyBackupAndRestoreButton ?? 'Backup & Restore';
    final emergencyTryRestartAppButton =
        l10n?.emergencyTryRestartAppButton ?? 'Try Restart';
    final emergencyExitAppButton = l10n?.emergencyExitAppButton ?? 'Exit App';
    final emergencyPersistentIssueHint = l10n?.emergencyPersistentIssueHint ??
        'If the issue persists, please contact support.';
    return Scaffold(
      appBar: AppBar(
        title: Text(emergencyModeTitle),
        backgroundColor: Colors.red,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                emergencyAppStartFailedTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                emergencyAppStartFailedDesc,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emergencyErrorLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(error),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: Text(emergencyTechnicalDetails),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.grey.shade100,
                      child: SelectableText(
                        stackTrace,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EmergencyBackupPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.backup),
                label: Text(emergencyBackupAndRestoreButton),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  // 尝试重新启动应用
                  restartApp();
                },
                icon: const Icon(Icons.refresh),
                label: Text(emergencyTryRestartAppButton),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  // 退出应用
                  exit(0);
                },
                icon: const Icon(Icons.exit_to_app),
                label: Text(emergencyExitAppButton),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  foregroundColor: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                emergencyPersistentIssueHint,
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void restartApp() {
    // 重新启动应用的逻辑
    try {
      // 清理全局状态
      _isEmergencyMode = false;
      _deferredErrors.clear();

      // 重新运行main函数
      main();
    } catch (e) {
      logDebug('重启应用失败: $e');
      // 如果重启失败,尝试导航到主页
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
        );
      }
    }
  }
}

/// 极端情况下的备份恢复页面,即使在数据库完全损坏的情况下也能工作
class EmergencyBackupPage extends StatefulWidget {
  const EmergencyBackupPage({super.key});

  @override
  State<EmergencyBackupPage> createState() => _EmergencyBackupPageState();
}

class _EmergencyBackupPageState extends State<EmergencyBackupPage> {
  bool _isLoading = false;
  String? _statusMessage;
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.emergencyBackupPageTitle),
        backgroundColor: Colors.orange,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.data_saver_on, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                l10n.emergencyBackupToolTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.emergencyBackupToolDesc,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              if (_isLoading)
                Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_statusMessage ?? l10n.emergencyProcessing),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _exportDatabaseFile,
                      icon: const Icon(Icons.folder),
                      label: Text(l10n.emergencyExportDatabaseButton),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        try {
                          Navigator.of(context).pushNamed('/backup_restore');
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(l10n.emergencyOpenBackupFailed('$e')),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.backup),
                      label: Text(l10n.emergencyOpenBackupPageButton),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              if (_statusMessage != null && !_isLoading)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        _hasError ? Colors.red.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: _hasError
                          ? Colors.red.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                l10n.emergencyExportHint,
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportDatabaseFile() async {
    final l10n = AppLocalizations.of(this.context);
    setState(() {
      _isLoading = true;
      _statusMessage = l10n.emergencyLocatingDatabase;
      _hasError = false;
    });

    try {
      // 获取数据库文件路径
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = join(appDir.path, 'databases');
      final dbFile = File(join(dbPath, 'thoughtecho.db'));
      final oldDbFile = File(join(dbPath, 'mind_trace.db'));

      // 确认文件存在
      if (!dbFile.existsSync() && !oldDbFile.existsSync()) {
        setState(() {
          _isLoading = false;
          _statusMessage = l10n.emergencyDatabaseNotFound;
          _hasError = true;
        });
        return;
      }

      // 使用存在的文件
      final sourceFile = dbFile.existsSync() ? dbFile : oldDbFile;

      setState(() {
        _statusMessage = l10n.emergencyPreparingExport;
      });

      // 创建一个导出目录
      final downloadsDir = Directory(join(appDir.path, 'Downloads'));
      if (!downloadsDir.existsSync()) {
        await downloadsDir.create(recursive: true);
      }

      // 创建导出文件名
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final exportFileName = 'thoughtecho_emergency_$timestamp.db';
      final exportFile = File(join(downloadsDir.path, exportFileName));

      // 复制文件
      setState(() {
        _statusMessage = l10n.emergencyCopyingFile;
      });

      await sourceFile.copy(exportFile.path);

      setState(() {
        _isLoading = false;
        _statusMessage = l10n.emergencyDatabaseExported(exportFile.path);
        _hasError = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = l10n.emergencyExportFailed('$e');
        _hasError = true;
      });
    }
  }
}
