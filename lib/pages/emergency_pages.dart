part of '../main.dart';

/// 紧急恢复页面，在数据库初始化失败时显示
class EmergencyRecoveryPage extends StatelessWidget {
  const EmergencyRecoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final shapeTokens = AppShapeTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.emergencyRecoveryTitle),
        backgroundColor: colorScheme.errorContainer,
        foregroundColor: colorScheme.onErrorContainer,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.emergencyRecoveryHeading,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.emergencyRecoveryDescription,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () async {
                    if (!context.mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BackupRestorePage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.backup),
                  label: Text(l10n.emergencyBackupAndRestoreButton),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(shapeTokens.buttonRadius),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final databaseService = DatabaseService();
                      databaseService.reinitialize();
                      await databaseService.initializeNewDatabase();

                      if (!context.mounted) return;

                      await Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HomePage(),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;

                      AppSnackBar.error(
                        context,
                        l10n.emergencyReinitializeFailed('$e'),
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.emergencyTryRestartAppButton),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(shapeTokens.buttonRadius),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  l10n.emergencyRecoveryHint,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
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

/// 极端情况下的应急应用，当初始化完全失败时启动
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
      navigatorKey: navigatorKey,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior: const AppScrollBehavior(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(boldText: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD32F2F),
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

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final shapeTokens = AppShapeTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(emergencyModeTitle),
        backgroundColor: colorScheme.errorContainer,
        foregroundColor: colorScheme.onErrorContainer,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  emergencyAppStartFailedTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  emergencyAppStartFailedDesc,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          emergencyErrorLabel,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          error,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: Text(emergencyTechnicalDetails),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(shapeTokens.cardRadius),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            stackTrace,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(shapeTokens.buttonRadius),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    restartApp();
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(emergencyTryRestartAppButton),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(shapeTokens.buttonRadius),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    exit(0);
                  },
                  icon: const Icon(Icons.exit_to_app),
                  label: Text(emergencyExitAppButton),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(shapeTokens.buttonRadius),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  emergencyPersistentIssueHint,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
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

  void restartApp() {
    try {
      _isEmergencyMode = false;
      getAndClearDeferredErrors();

      main();
    } catch (e) {
      logDebug('重启应用失败: $e');
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
        );
      }
    }
  }
}

/// 极端情况下的备份恢复页面，即使在数据库完全损坏的情况下也能工作
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final shapeTokens = AppShapeTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.emergencyBackupPageTitle),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.data_saver_on, size: 64, color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  l10n.emergencyBackupToolTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.emergencyBackupToolDesc,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                if (_isLoading)
                  AppLoadingView(
                    message: _statusMessage ?? l10n.emergencyProcessing,
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
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(shapeTokens.buttonRadius),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          try {
                            Navigator.of(context).pushNamed('/backup_restore');
                          } catch (e) {
                            AppSnackBar.error(
                              context,
                              l10n.emergencyOpenBackupFailed('$e'),
                            );
                          }
                        },
                        icon: const Icon(Icons.backup),
                        label: Text(l10n.emergencyOpenBackupPageButton),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(shapeTokens.buttonRadius),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_statusMessage != null && !_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Card(
                      elevation: 0,
                      color: _hasError
                          ? colorScheme.errorContainer
                          : colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(shapeTokens.cardRadius),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            color: _hasError
                                ? colorScheme.onErrorContainer
                                : colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
                Text(
                  l10n.emergencyExportHint,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
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

  Future<void> _exportDatabaseFile() async {
    final l10n = AppLocalizations.of(this.context);
    setState(() {
      _isLoading = true;
      _statusMessage = l10n.emergencyLocatingDatabase;
      _hasError = false;
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = join(appDir.path, 'databases');
      final dbFile = File(join(dbPath, 'thoughtecho.db'));
      final oldDbFile = File(join(dbPath, 'mind_trace.db'));

      if (!dbFile.existsSync() && !oldDbFile.existsSync()) {
        setState(() {
          _isLoading = false;
          _statusMessage = l10n.emergencyDatabaseNotFound;
          _hasError = true;
        });
        return;
      }

      final sourceFile = dbFile.existsSync() ? dbFile : oldDbFile;

      setState(() {
        _statusMessage = l10n.emergencyPreparingExport;
      });

      final downloadsDir = Directory(join(appDir.path, 'Downloads'));
      if (!downloadsDir.existsSync()) {
        await downloadsDir.create(recursive: true);
      }

      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final exportFileName = 'thoughtecho_emergency_$timestamp.db';
      final exportFile = File(join(downloadsDir.path, exportFileName));

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
