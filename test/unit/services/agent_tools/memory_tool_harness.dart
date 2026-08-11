import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../../test_harness.dart';

/// `remember` / `recall` 两个工具测试共用的脚手架。
///
/// 两边都要一套内存记忆库 + 干净的 SettingsService，抽在这里，免得两个文件
/// 各抄一份 setUp。
class MemoryToolHarness {
  late SettingsService settingsService;
  late AgentMemoryService memory;

  /// 在 `main()` 顶层调一次。
  static void initializeBinding() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  Future<void> setUpAll() async {
    await TestHarness.initialize();
    await MMKVService().init();
  }

  Future<void> setUp() async {
    await MMKVService().clear();
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    settingsService = SettingsService(await SharedPreferences.getInstance());
    memory = AgentMemoryService(
      settingsService: settingsService,
      databasePath: inMemoryDatabasePath,
    );
  }

  Future<void> tearDown() async {
    memory.dispose();
    SharedPreferences.resetStatic();
  }

  Future<void> tearDownAll() => TestHarness.tearDown();
}

ToolCall toolCall(String name, Map<String, Object?> arguments) =>
    ToolCall(id: 'call-1', name: name, arguments: arguments);

Map<String, Object?> decodeResult(ToolResult result) =>
    jsonDecode(result.content) as Map<String, Object?>;
