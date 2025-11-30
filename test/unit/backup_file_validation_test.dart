import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/streaming_backup_processor.dart';
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';

void main() {
  group('备份文件验证测试', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_test_');
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('应该正确检测ZIP文件类型', () async {
      // 创建一个简单的ZIP文件
      final zipPath = '${tempDir.path}/test_backup.zip';
      final archive = Archive();

      // 添加一个测试文件
      final testData = {'test': 'data'};
      final jsonContent = json.encode(testData);
      final file = ArchiveFile(
        'backup_data.json',
        jsonContent.length,
        jsonContent.codeUnits,
      );
      archive.addFile(file);

      // 写入ZIP文件
      final zipData = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipData);

      // 测试类型检测
      final type = await StreamingBackupProcessor.detectBackupType(zipPath);
      expect(type, equals('zip'));
    });

    test('应该正确检测JSON文件类型', () async {
      // 创建一个JSON文件
      final jsonPath = '${tempDir.path}/test_backup.json';
      final testData = {'test': 'data'};
      await File(jsonPath).writeAsString(json.encode(testData));

      // 测试类型检测
      final type = await StreamingBackupProcessor.detectBackupType(jsonPath);
      expect(type, equals('json'));
    });

    test('应该能够验证包含backup_data.json的ZIP文件', () async {
      // 创建一个包含backup_data.json的ZIP文件
      final zipPath = '${tempDir.path}/valid_backup.zip';
      final archive = Archive();

      // 创建有效的备份数据结构
      final backupData = {
        'version': '1.2.0',
        'createdAt': DateTime.now().toIso8601String(),
        'notes': {
          'metadata': {
            'app': '心迹',
            'version': 1,
            'exportTime': DateTime.now().toIso8601String(),
          },
          'categories': [],
          'quotes': [],
        },
        'settings': {},
        'ai_analysis': [],
      };

      final jsonContent = json.encode(backupData);
      final file = ArchiveFile(
        'backup_data.json',
        jsonContent.length,
        jsonContent.codeUnits,
      );
      archive.addFile(file);

      // 写入ZIP文件
      final zipData = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipData);

      // 测试验证
      final isValid = await StreamingBackupProcessor.validateBackupFile(
        zipPath,
      );
      expect(isValid, isTrue);
    });

    test('应该能够验证包含data.json的ZIP文件（向后兼容）', () async {
      // 创建一个包含data.json的ZIP文件（旧格式）
      final zipPath = '${tempDir.path}/legacy_backup.zip';
      final archive = Archive();

      // 创建有效的备份数据结构
      final backupData = {
        'version': '1.2.0',
        'createdAt': DateTime.now().toIso8601String(),
        'notes': {
          'metadata': {
            'app': '心迹',
            'version': 1,
            'exportTime': DateTime.now().toIso8601String(),
          },
          'categories': [],
          'quotes': [],
        },
        'settings': {},
        'ai_analysis': [],
      };

      final jsonContent = json.encode(backupData);
      final file = ArchiveFile(
        'data.json',
        jsonContent.length,
        jsonContent.codeUnits,
      );
      archive.addFile(file);

      // 写入ZIP文件
      final zipData = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipData);

      // 测试验证
      final isValid = await StreamingBackupProcessor.validateBackupFile(
        zipPath,
      );
      expect(isValid, isTrue);
    });

    test('应该拒绝不包含数据文件的ZIP文件', () async {
      // 创建一个不包含数据文件的ZIP文件
      final zipPath = '${tempDir.path}/invalid_backup.zip';
      final archive = Archive();

      // 添加一个无关的文件
      final file = ArchiveFile('other_file.txt', 4, 'test'.codeUnits);
      archive.addFile(file);

      // 写入ZIP文件
      final zipData = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipData);

      // 测试验证
      final isValid = await StreamingBackupProcessor.validateBackupFile(
        zipPath,
      );
      expect(isValid, isFalse);
    });

    test('应该能够处理ZIP文件中的文件列表', () async {
      // 创建一个包含多个文件的ZIP文件
      final zipPath = '${tempDir.path}/multi_file_backup.zip';
      final archive = Archive();

      // 添加多个文件
      final files = [
        'backup_data.json',
        'media/image1.jpg',
        'media/image2.png',
        'other_file.txt',
      ];

      for (final fileName in files) {
        final content = fileName == 'backup_data.json'
            ? json.encode({'test': 'data'})
            : 'test content';
        final file = ArchiveFile(fileName, content.length, content.codeUnits);
        archive.addFile(file);
      }

      // 写入ZIP文件
      final zipData = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipData);

      // 测试验证
      final isValid = await StreamingBackupProcessor.validateBackupFile(
        zipPath,
      );
      expect(isValid, isTrue);
    });
  });
}
