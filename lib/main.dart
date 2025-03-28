import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' hide Context;  // 避免Context类型冲突
import 'package:mind_trace/services/database_service.dart';
import 'package:mind_trace/models/quote_model.dart';

Future<void> initializeDatabasePlatform() async {
  if (!kIsWeb && Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await initializeDatabasePlatform();
    final databaseService = DatabaseService();
    await databaseService.database; // 预初始化

    runApp(
      ChangeNotifierProvider(
        create: (_) => databaseService,
        child: const MyApp(),
      ),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('应用启动失败', style: TextStyle(fontSize: 20)),
                Text('错误: ${e.toString()}', style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => main(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '心迹笔记',
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Quote>> _quotesFuture;
  late DatabaseService _databaseService;

  @override
  void initState() {
    super.initState();
    _databaseService = Provider.of<DatabaseService>(context, listen: false);
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _quotesFuture = _databaseService.getQuotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的笔记')),
      body: FutureBuilder<List<Quote>>(
        future: _quotesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          final quotes = snapshot.data ?? [];
          return ListView.builder(
            itemCount: quotes.length,
            itemBuilder: (ctx, index) => ListTile(
              title: Text(quotes[index].content),
              subtitle: Text(quotes[index].date),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _addSampleNote();
          _refreshData();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addSampleNote() async {
    await _databaseService.saveQuote(Quote(
      date: DateTime.now().toString(),
      content: '新笔记 ${DateTime.now().hour}:${DateTime.now().minute}',
    ));
  }
}
