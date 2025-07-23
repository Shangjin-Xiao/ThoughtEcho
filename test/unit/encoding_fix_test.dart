import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/streaming_backup_processor.dart';
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';

void main() {
  group('编码修复测试', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('encoding_test_');
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('应该正确处理包含中文的JSON文件', () async {
      // 创建包含中文的测试数据
      final testData = {
        'title': '测试笔记',
        'content': '这是一个包含中文的测试内容。包含特殊字符：你好世界！',
        'category': '日记',
        'tags': ['测试', '中文', '编码'],
      };

      // 创建JSON文件
      final jsonPath = '${tempDir.path}/test_chinese.json';
      final jsonFile = File(jsonPath);
      await jsonFile.writeAsString(json.encode(testData), encoding: utf8);

      // 测试解析
      final result =
          await StreamingBackupProcessor.parseJsonBackupStreaming(jsonPath);

      // 验证中文内容是否正确
      expect(result['title'], equals('测试笔记'));
      expect(result['content'], equals('这是一个包含中文的测试内容。包含特殊字符：你好世界！'));
      expect(result['category'], equals('日记'));
      expect(result['tags'], equals(['测试', '中文', '编码']));
    });

    test('应该正确处理包含中文的ZIP文件', () async {
      // 创建包含中文的测试数据
      final testData = {
        'version': '1.2.0',
        'createdAt': DateTime.now().toIso8601String(),
        'notes': {
          'metadata': {
            'app': '心迹',
            'version': 1,
            'exportTime': DateTime.now().toIso8601String(),
          },
          'categories': [
            {'id': 1, 'name': '日记', 'color': '#FF5722'},
            {'id': 2, 'name': '工作笔记', 'color': '#2196F3'},
          ],
          'quotes': [
            {
              'id': 1,
              'content': '这是一个包含中文的测试笔记内容。',
              'title': '测试标题',
              'category': '日记',
              'tags': '测试,中文,编码',
              'date': DateTime.now().toIso8601String(),
            },
          ],
        },
        'settings': {
          'theme': '深色主题',
          'language': '中文',
        },
        'ai_analysis': [],
      };

      // 创建ZIP文件
      final zipPath = '${tempDir.path}/test_chinese.zip';
      final archive = Archive();

      // 将JSON数据编码为UTF-8字节
      final jsonContent = json.encode(testData);
      final jsonBytes = utf8.encode(jsonContent);
      final file = ArchiveFile('backup_data.json', jsonBytes.length, jsonBytes);
      archive.addFile(file);

      // 写入ZIP文件
      final zipData = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipData!);

      // 测试解析
      final result =
          await StreamingBackupProcessor.processZipBackupStreaming(zipPath);

      // 验证中文内容是否正确
      expect(result['notes']['categories'][0]['name'], equals('日记'));
      expect(result['notes']['categories'][1]['name'], equals('工作笔记'));
      expect(
          result['notes']['quotes'][0]['content'], equals('这是一个包含中文的测试笔记内容。'));
      expect(result['notes']['quotes'][0]['title'], equals('测试标题'));
      expect(result['settings']['theme'], equals('深色主题'));
      expect(result['settings']['language'], equals('中文'));
    });

    test('应该正确处理大文件中的中文内容', () async {
      // 创建包含大量中文内容的测试数据
      final largeContent = '这是一个包含大量中文内容的测试。' * 1000; // 重复1000次
      final testData = {
        'title': '大文件测试',
        'content': largeContent,
        'metadata': {
          'description': '这是一个用于测试大文件中文编码的测试数据',
          'tags': ['大文件', '中文', '编码测试'],
        },
      };

      // 创建大JSON文件
      final jsonPath = '${tempDir.path}/large_chinese.json';
      final jsonFile = File(jsonPath);
      await jsonFile.writeAsString(json.encode(testData), encoding: utf8);

      // 验证文件大小
      final fileSize = await jsonFile.length();
      print('测试文件大小: ${(fileSize / 1024).toStringAsFixed(1)}KB');

      // 测试解析
      final result =
          await StreamingBackupProcessor.parseJsonBackupStreaming(jsonPath);

      // 验证中文内容是否正确
      expect(result['title'], equals('大文件测试'));
      expect(result['content'], equals(largeContent));
      expect(result['metadata']['description'], equals('这是一个用于测试大文件中文编码的测试数据'));
      expect(result['metadata']['tags'], equals(['大文件', '中文', '编码测试']));
    });
  });
}
