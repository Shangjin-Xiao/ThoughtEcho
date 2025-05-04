import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/backup_restore_page.dart'; // 保持导入
import 'services/settings_service.dart'; // 需要 SettingsService 来决定初始路由
import 'services/log_service.dart'; // 可能需要 LogService

// 应用的根 Widget
class AppWidget extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final bool isEmergencyMode;
  final bool showUpdateReady;
  final bool showFullOnboarding;
  final String currentVersion;

  const AppWidget({
    super.key,
    required this.navigatorKey,
    required this.isEmergencyMode,
    required this.showUpdateReady,
    required this.showFullOnboarding,
    required this.currentVersion,
  });

  @override
  Widget build(BuildContext context) {
    // 使用 watch 监听 AppTheme 的变化
    final appTheme = context.watch<AppTheme>();
    // 读取 SettingsService 来确定初始路由等
    final settingsService = context.read<SettingsService>();

    // 确定初始路由
    String initialRoute = '/'; // 默认主页
    if (isEmergencyMode) {
      initialRoute = '/emergency'; // 可以定义一个紧急模式页面路由
    } else if (showFullOnboarding) {
      initialRoute = '/onboarding';
    } else if (showUpdateReady) {
      // 如果有更新提示，也可能先跳转到特定页面或显示对话框
      // 这里暂时还指向主页，具体逻辑可在 HomePage 实现
      initialRoute = '/update_ready'; // 可以定义一个更新提示路由
    }

    // 如果初始路由是主页，则显示 HomePage
    Widget initialWidget = HomePage();
    if (initialRoute == '/onboarding') {
      initialWidget = OnboardingPage(onOnboardingComplete: () {
            // 完成引导后，更新设置并导航到主页
            settingsService.setHasCompletedOnboarding(true);
            settingsService.setAppVersion(currentVersion); // 记录当前版本
            navigatorKey.currentState?.pushReplacementNamed('/');
          });
    } else if (initialRoute == '/update_ready') {
      // 可以创建一个专门的 UpdateReadyPage 或在 HomePage 处理
      // 这里暂时用一个简单的占位符
      initialWidget = _buildUpdateReadyPlaceholder(context);
    } else if (initialRoute == '/emergency') {
      initialWidget = _buildEmergencyPlaceholder(context);
    }


    return MaterialApp(
      navigatorKey: navigatorKey, // 设置全局 navigatorKey
      title: 'ThoughtEcho',
      theme: appTheme.lightTheme,
      darkTheme: appTheme.darkTheme,
      themeMode: appTheme.themeMode,
      // 使用 onGenerateRoute 处理命名路由
      onGenerateRoute: (settings) {
        Widget page;
        switch (settings.name) {
          case '/':
            page = HomePage(); // 确保 HomePage 处理 showUpdateReady 状态
            break;
          case '/onboarding':
            page = OnboardingPage(onOnboardingComplete: () {
              settingsService.setHasCompletedOnboarding(true);
              settingsService.setAppVersion(currentVersion);
              navigatorKey.currentState?.pushReplacementNamed('/');
            });
            break;
          case '/backup_restore':
            page = const BackupRestorePage();
            break;
           case '/update_ready': // 添加更新准备路由
             page = _buildUpdateReadyPlaceholder(context);
             break;
           case '/emergency': // 添加紧急模式路由
             page = _buildEmergencyPlaceholder(context);
             break;
          default:
            // 如果路由未定义，可以显示一个错误页面或返回主页
            page = Scaffold(
              appBar: AppBar(title: const Text('未知页面')),
              body: const Center(child: Text('找不到您要访问的页面。')),
            );
        }
        // 应用默认过渡动画
        return MaterialPageRoute(builder: (_) => page, settings: settings);
      },
      // 设置初始 Widget 而不是 initialRoute，避免重复构建
      home: initialWidget,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''), // English, no country code
        Locale('zh', ''), // Chinese, no country code
      ],
      // locale: Locale('zh'), // 可以根据用户设置动态设置
      debugShowCheckedModeBanner: false, // Release 时应为 false
    );
  }

  // 更新准备页面的占位符
  Widget _buildUpdateReadyPlaceholder(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('应用已更新')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('ThoughtEcho 已更新到新版本！'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                   // 在这里可以添加数据迁移逻辑（如果需要异步操作，需要更复杂的处理）
                   // 迁移完成后更新版本号并跳转
                   context.read<SettingsService>().setAppVersion(currentVersion);
                   navigatorKey.currentState?.pushReplacementNamed('/');
                },
                child: const Text('继续'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 紧急模式页面的占位符
  Widget _buildEmergencyPlaceholder(BuildContext context) {
     return Scaffold(
       appBar: AppBar(title: const Text('紧急模式')),
       body: Center(
         child: Padding(
           padding: const EdgeInsets.all(16.0),
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               const Icon(Icons.warning_amber_rounded, size: 60, color: Colors.orange),
               const SizedBox(height: 20),
               const Text(
                 '抱歉，应用遇到了一些问题，已进入紧急模式。'
                 '\n部分功能可能无法使用。建议尝试备份数据。',
                 textAlign: TextAlign.center,
               ),
               const SizedBox(height: 20),
               ElevatedButton.icon(
                 icon: const Icon(Icons.backup),
                 label: const Text('尝试备份数据'),
                 onPressed: () {
                    navigatorKey.currentState?.pushNamed('/backup_restore');
                 },
                 style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
               ),
             ],
           ),
         ),
       ),
     );
  }

} 