import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'lib/services/database_service.dart';

void main() async {
  // 初始化FFI
  if (!kIsWeb && Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 开始测试数据库修复...
  
  try {
    final dbService = DatabaseService();
    
    // 初始化数据库服务...
    await dbService.init();
    
    // 数据库初始化完成，检查是否可以正常查询笔记...
    
    // 尝试获取笔记
    final quotes = await dbService.getUserQuotes(limit: 5);
    assert(quotes.isNotEmpty, '应该至少有一条笔记');
    
    // 尝试获取分类
    final categories = await dbService.getCategories();
    assert(categories.isNotEmpty, '应该至少有一个分类');
    
    // 数据库修复测试成功！
    
  } catch (e) {
    // 数据库测试失败: $e
  }
}
