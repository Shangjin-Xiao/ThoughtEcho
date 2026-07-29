import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';

/// 回归测试：同步包必须真正含有 backup_data.json。
///
/// 历史缺陷：ZipFileEncoder.addFile 未 await，closeSync 先于条目写入执行，
/// 上传到云端的是空 ZIP，之后每台设备同步都失败于“云端同步文件缺少
/// backup_data.json”，且因为解析在上传步骤之前抛出，永远无法自愈。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('webdav_sync_zip_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('packSyncZip 打出的包含有可解析的 backup_data.json', () async {
    final payload = {
      'version': '1',
      'categories': [
        {'id': 'c1', 'name': '默认'},
      ],
      'quotes': [
        {'id': 'q1', 'content': '测试笔记'},
      ],
    };
    final jsonPath = '${tempDir.path}/sync.json';
    final zipPath = '${tempDir.path}/sync.zip';
    await File(jsonPath).writeAsString(json.encode(payload));

    await WebDAVSyncService.packSyncZip(jsonPath, zipPath);

    final inputStream = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(inputStream);
      final entry = archive.findFile('backup_data.json');
      expect(entry, isNotNull, reason: '同步包缺少 backup_data.json');

      final decoded = json.decode(utf8.decode(entry!.content));
      expect(decoded['quotes'], hasLength(1));
      expect(decoded['categories'], hasLength(1));
    } finally {
      inputStream.closeSync();
    }
  });

  test('打包大 JSON 时条目内容完整写入', () async {
    final quotes = List.generate(
      2000,
      (i) => {'id': 'q$i', 'content': '笔记内容 $i' * 20},
    );
    final jsonPath = '${tempDir.path}/big.json';
    final zipPath = '${tempDir.path}/big.zip';
    await File(jsonPath).writeAsString(
      json.encode({'categories': <dynamic>[], 'quotes': quotes}),
    );

    await WebDAVSyncService.packSyncZip(jsonPath, zipPath);

    final inputStream = InputFileStream(zipPath);
    try {
      final entry =
          ZipDecoder().decodeStream(inputStream).findFile('backup_data.json');
      final decoded = json.decode(utf8.decode(entry!.content));
      expect(decoded['quotes'], hasLength(2000));
    } finally {
      inputStream.closeSync();
    }
  });
}
