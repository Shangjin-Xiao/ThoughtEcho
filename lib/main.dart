import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'services/database_service.dart';
import 'services/settings_service.dart';
import 'services/ai_service.dart';
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final settingsService = await SettingsService.create();
  final databaseService = DatabaseService();
  await databaseService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => settingsService),
        ChangeNotifierProvider(create: (_) => databaseService),
        ChangeNotifierProxyProvider<SettingsService, AIService>(
          create: (context) => AIService(
            settingsService: context.read<SettingsService>(),
          ),
          update: (context, settings, previous) =>
              previous ?? AIService(settingsService: settings),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '心迹',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
