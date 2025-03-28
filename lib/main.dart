import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:permission_handler/permission_handler.dart';

// 数据库服务
class DatabaseService with ChangeNotifier {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'mind_trace.db');
    
    debugPrint('数据库路径: $path');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE quotes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER
          )
        ''');
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA journal_mode=WAL');
      },
    );
  }

  Future<int> addQuote(String content) async {
    final db = await database;
    final id = await db.insert('quotes', {
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000
    });
    notifyListeners();
    return id;
  }

  Future<List<Map<String, dynamic>>> getQuotes() async {
    final db = await database;
    return await db.query('quotes', orderBy: 'created_at DESC');
  }
}

// 主应用
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android权限处理
  if (Platform.isAndroid) {
    final status = await Permission.storage.request();
    if (status.isDenied) {
      await openAppSettings();
    }
  }

  // Windows平台初始化
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 带重试的初始化
  int retryCount = 0;
  while (retryCount < 3) {
    try {
      final databaseService = DatabaseService();
      await databaseService.database; // 预初始化

      runApp(
        ChangeNotifierProvider(
          create: (_) => databaseService,
          child: const MyApp(),
        ),
      );
      return;
    } catch (e) {
      debugPrint('初始化失败 (尝试 ${retryCount + 1}): $e');
      retryCount++;
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  // 全部重试失败后显示错误界面
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('应用启动失败', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: main,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
  late Future<List<Map<String, dynamic>>> _quotesFuture;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _quotesFuture = Provider.of<DatabaseService>(context, listen: false)
          .getQuotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的笔记')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _quotesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('错误: ${snapshot.error}'));
          }
          final quotes = snapshot.data ?? [];
          return ListView.builder(
            itemCount: quotes.length,
            itemBuilder: (ctx, index) => ListTile(
              title: Text(quotes[index]['content'] ?? ''),
              subtitle: Text(
                DateTime.fromMillisecondsSinceEpoch(
                        (quotes[index]['created_at'] ?? 0) * 1000)
                    .toString(),
              ),
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
    final db = Provider.of<DatabaseService>(context, listen: false);
    await db.addQuote('新笔记 ${DateTime.now().toIso8601String()}');
  }
}
