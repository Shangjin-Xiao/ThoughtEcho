import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
// 仅在 Windows 平台下使用 sqflite_common_ffi，其它平台直接使用 sqflite 默认实现
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    if (dart.library.io) 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/ai_analysis_model.dart';
import 'package:uuid/uuid.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// AI分析数据库服务
///
/// 专门用于管理AI分析结果，使用单独的数据库文件存储
class AIAnalysisDatabaseService extends ChangeNotifier {
  static Database? _database;
  final _uuid = const Uuid();

  // 内存存储，用于 Web 平台或调试存储
  final List<AIAnalysis> _memoryStore = [];

  // 流控制器，用于广播分析结果变更
  final _analysesController = StreamController<List<AIAnalysis>>.broadcast();

  // 单例模式
  static final AIAnalysisDatabaseService _instance =
      AIAnalysisDatabaseService._internal();

  factory AIAnalysisDatabaseService() {
    return _instance;
  }

  AIAnalysisDatabaseService._internal();

  /// 初始化数据库
  Future<Database> get database async {
    if (_database != null) return _database!;

    // 初始化平台特定代码
    if (Platform.isWindows || Platform.isLinux) {
      // 为Windows和Linux平台设置sqflite_ffi
      sqfliteFfiInit();
      _database = await databaseFactoryFfi.openDatabase(
        await _getDatabasePath(),
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _createDatabase,
          onUpgrade: _onUpgradeDatabase,
        ),
      );
    } else {
      // 为其他平台使用标准sqflite
      _database = await openDatabase(
        await _getDatabasePath(),
        version: 1,
        onCreate: _createDatabase,
        onUpgrade: _onUpgradeDatabase,
      );
    }

    return _database!;
  }

  /// 获取数据库文件路径
  Future<String> _getDatabasePath() async {
    if (Platform.isWindows || Platform.isLinux) {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      return join(documentsDirectory.path, 'ai_analyses.db');
    } else {
      return join(await getDatabasesPath(), 'ai_analyses.db');
    }
  }

  /// 创建数据库表
  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ai_analyses(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        analysis_type TEXT NOT NULL,
        analysis_style TEXT NOT NULL,
        custom_prompt TEXT,
        created_at TEXT NOT NULL,
        related_quote_ids TEXT,
        quote_count INTEGER
      )
    ''');
  }

  /// 数据库升级处理
  Future<void> _onUpgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // 这里处理未来可能的数据库升级逻辑
    if (oldVersion < 2) {
      // 版本1到版本2的迁移代码（如果需要）
    }
  }

  /// 关闭数据库连接
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    if (!_analysesController.isClosed) {
      await _analysesController.close();
    }
  }

  /// 保存AI分析结果
  Future<AIAnalysis> saveAnalysis(AIAnalysis analysis) async {
    try {
      final newAnalysis = analysis.copyWith(
        id: analysis.id ?? _uuid.v4(),
        createdAt:
            analysis.createdAt.isNotEmpty
                ? analysis.createdAt
                : DateTime.now().toIso8601String(),
      );

      if (kIsWeb) {
        // Web平台使用内存存储
        final existingIndex = _memoryStore.indexWhere(
          (item) => item.id == newAnalysis.id,
        );
        if (existingIndex >= 0) {
          _memoryStore[existingIndex] = newAnalysis;
        } else {
          _memoryStore.add(newAnalysis);
        }
      } else {
        // 非Web平台使用SQLite
        final db = await database;
        await db.insert(
          'ai_analyses',
          newAnalysis.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 通知监听器数据已更新
      notifyListeners();
      _notifyAnalysesChanged();

      return newAnalysis;
    } catch (e) {
      AppLogger.e('保存AI分析失败: $e', error: e, source: 'AIAnalysisDB');
      rethrow;
    }
  }

  /// 获取所有AI分析结果
  Future<List<AIAnalysis>> getAllAnalyses() async {
    try {
      if (kIsWeb) {
        // Web平台使用内存存储
        return List.from(_memoryStore);
      } else {
        // 非Web平台使用SQLite
        final db = await database;
        final List<Map<String, dynamic>> maps = await db.query(
          'ai_analyses',
          orderBy: 'created_at DESC',
        );

        return List.generate(maps.length, (i) {
          return AIAnalysis.fromJson(maps[i]);
        });
      }
    } catch (e) {
      AppLogger.e('获取AI分析列表失败: $e', error: e, source: 'AIAnalysisDB');
      return [];
    }
  }

  /// 根据ID获取单个分析结果
  Future<AIAnalysis?> getAnalysisById(String id) async {
    try {
      if (kIsWeb) {
        // Web平台使用内存存储
        return _memoryStore.firstWhere((item) => item.id == id);
      } else {
        // 非Web平台使用SQLite
        final db = await database;
        final List<Map<String, dynamic>> maps = await db.query(
          'ai_analyses',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );

        if (maps.isEmpty) return null;
        return AIAnalysis.fromJson(maps.first);
      }
    } catch (e) {
      AppLogger.e('获取AI分析失败: $e', error: e, source: 'AIAnalysisDB');
      return null;
    }
  }

  /// 删除分析结果
  Future<bool> deleteAnalysis(String id) async {
    try {
      if (kIsWeb) {
        // Web平台使用内存存储
        _memoryStore.removeWhere((item) => item.id == id);
      } else {
        // 非Web平台使用SQLite
        final db = await database;
        await db.delete('ai_analyses', where: 'id = ?', whereArgs: [id]);
      }

      // 通知监听器数据已更新
      notifyListeners();
      _notifyAnalysesChanged();

      return true;
    } catch (e) {
      AppLogger.e('删除AI分析失败: $e', error: e, source: 'AIAnalysisDB');
      return false;
    }
  }

  /// 删除所有分析结果
  Future<bool> deleteAllAnalyses() async {
    try {
      if (kIsWeb) {
        // Web平台使用内存存储
        _memoryStore.clear();
      } else {
        // 非Web平台使用SQLite
        final db = await database;
        await db.delete('ai_analyses');
      }

      // 通知监听器数据已更新
      notifyListeners();
      _notifyAnalysesChanged();

      return true;
    } catch (e) {
      AppLogger.e('删除所有AI分析失败: $e', error: e, source: 'AIAnalysisDB');
      return false;
    }
  }

  /// 按照分析类型搜索
  Future<List<AIAnalysis>> searchAnalysesByType(String analysisType) async {
    try {
      if (kIsWeb) {
        // Web平台使用内存存储
        return _memoryStore
            .where((item) => item.analysisType == analysisType)
            .toList();
      } else {
        // 非Web平台使用SQLite
        final db = await database;
        final List<Map<String, dynamic>> maps = await db.query(
          'ai_analyses',
          where: 'analysis_type = ?',
          whereArgs: [analysisType],
          orderBy: 'created_at DESC',
        );

        return List.generate(maps.length, (i) {
          return AIAnalysis.fromJson(maps[i]);
        });
      }
    } catch (e) {
      AppLogger.e('按分析类型搜索AI分析失败: $e', error: e, source: 'AIAnalysisDB');
      return [];
    }
  }

  /// 搜索AI分析内容
  Future<List<AIAnalysis>> searchAnalyses(String query) async {
    try {
      if (kIsWeb) {
        // Web平台使用内存存储
        return _memoryStore
            .where(
              (item) =>
                  item.title.toLowerCase().contains(query.toLowerCase()) ||
                  item.content.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      } else {
        // 非Web平台使用SQLite
        final db = await database;
        final List<Map<String, dynamic>> maps = await db.query(
          'ai_analyses',
          where: 'title LIKE ? OR content LIKE ?',
          whereArgs: ['%$query%', '%$query%'],
          orderBy: 'created_at DESC',
        );

        return List.generate(maps.length, (i) {
          return AIAnalysis.fromJson(maps[i]);
        });
      }
    } catch (e) {
      AppLogger.e('搜索AI分析失败: $e', error: e, source: 'AIAnalysisDB');
      return [];
    }
  }

  /// 获取流以监听分析列表变更
  Stream<List<AIAnalysis>> get analysesStream => _analysesController.stream;

  /// 通知分析列表已更改
  void _notifyAnalysesChanged() async {
    if (!_analysesController.isClosed) {
      final analyses = await getAllAnalyses();
      _analysesController.add(analyses);
    }
  }

  /// 从导出的JSON文件中恢复分析数据
  Future<int> restoreFromJson(String jsonStr) async {
    try {
      final List<dynamic> jsonList = json.decode(jsonStr);
      int count = 0;

      for (var item in jsonList) {
        if (item is Map<String, dynamic>) {
          final analysis = AIAnalysis.fromJson(item);
          await saveAnalysis(analysis);
          count++;
        }
      }

      return count;
    } catch (e) {
      AppLogger.e('从JSON恢复AI分析失败: $e', error: e, source: 'AIAnalysisDB');
      return 0;
    }
  }

  /// 将分析数据导出为JSON字符串
  Future<String> exportToJson() async {
    try {
      final analyses = await getAllAnalyses();
      final jsonList = analyses.map((analysis) => analysis.toJson()).toList();
      return json.encode(jsonList);
    } catch (e) {
      AppLogger.e('导出AI分析到JSON失败: $e', error: e, source: 'AIAnalysisDB');
      return '[]';
    }
  }

  @override
  void dispose() {
    // 关闭StreamController
    _analysesController.close();
    super.dispose();
  }
}
