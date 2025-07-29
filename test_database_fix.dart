import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'lib/services/database_service.dart';
import 'lib/utils/app_logger.dart';

void main() async {
  // 初始化FFI
  if (!kIsWeb && Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  print('开始测试数据库修复...');
  
  try {
    final dbService = DatabaseService();
    
    print('初始化数据库服务...');
    await dbService.init();
    
    print('数据库初始化完成，检查是否可以正常查询笔记...');
    
    // 尝试获取笔记
    final quotes = await dbService.getUserQuotes(limit: 5);
    print('成功获取 ${quotes.length} 条笔记');
    
    // 尝试获取分类
    final categories = await dbService.getCategories();
    print('成功获取 ${categories.length} 个分类');
    
    print('数据库修复测试成功！');
    
  } catch (e, stackTrace) {
    print('数据库测试失败: $e');
    print('堆栈跟踪: $stackTrace');
  }
}
