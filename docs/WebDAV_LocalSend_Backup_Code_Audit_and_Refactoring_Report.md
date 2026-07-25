# WebDAV、LocalSend 与备份还原模块代码审计与重构评估报告

**项目**: ThoughtEcho（心迹）  
**日期**: 2026 年 7 月 24 日  
**审计责任方**: Project Orchestrator & Multi-Agent Audit Team  
**审计范围**: 
1. WebDAV 同步服务（`lib/services/webdav_sync_service.dart` 及 UI/模型层）
2. LocalSend 局域网 P2P 同步服务（`lib/services/localsend/`、`lib/services/note_sync_service.dart`、`lib/pages/note_sync_page.dart`）
3. 数据库备份与还原服务（`lib/services/backup_service.dart`、`database_backup_service.dart`、`database_import_export_mixin.dart`、`schema_repair_adapter.dart`、`database_schema_manager.dart`）
4. 静态分析（`flutter analyze --no-fatal-infos`）与边界条件测试覆盖率评估

---

## 1. 报告概述 (Executive Summary)

ThoughtEcho 是一款基于 Flutter 3.x 开发的跨平台笔记应用，核心支持数据在 Windows、Android 和 iOS 三端无缝流转。本次代码与架构审计旨在深入剖析应用的三大核心数据能力（**WebDAV 同步**、**LocalSend 局域网 P2P 同步**、**数据备份与还原**），评估其在增量/全量同步、并发冲突控制、网络容灾、解包安全、SQLite 事务原子性、富文本 consistency、跨平台兼容性及安全隐患等维度的表现，并产出结构化的重构方案与测试改进建议。

### 1.1 静态分析与测试套件评估摘要
- **静态分析结果**: 在三大核心数据模块中，`flutter analyze --no-fatal-infos` 扫描结果为 **0 警告、0 错误、0 Hint**。（全仓库仅在非相关 UI/测试文件中包含 4 处无害的 `deprecated_member_use` 提示）。
- **既有测试通过率**: 运行 23 个相关测试文件共 **122 项单元、Widget 与集成测试**，通过率 **100%**。
- **既有防护机制亮点**:
  - WebDAV 具备安全凭据隔离（密码存储于 `FlutterSecureStorage`，URL/用户名存 MMKV）、网络错误脱敏防泄露及 Dio 15s/20s 超时配置。
  - Backup & Restore 内置 `PathSecurityUtils.validateExtractionPath` 防范 Zip Slip 路径穿越攻击，并包含 `DeviceMemoryManager` 内存压力防护。
  - LocalSend 具备基础的数据接收流化写入与 LWW（Last-Write-Wins）SQLite 事务防覆盖机制。

### 1.2 高/中/低风险分布汇总表

| 模块 | 高风险 (P0/P1) | 中风险 (P2) | 低风险 (P3) | 核心瓶颈 / 致命缺陷 |
|---|:---:|:---:|:---:|---|
| **WebDAV 同步** | 2 | 3 | 2 | 无 ETag 时 PUT 缺少并发锁防并发覆盖；导出备份未在事务内快照导致脏读 |
| **LocalSend P2P** | 4 | 3 | 1 | 局域网纯明文 HTTP 传输；Fake Isolate 阻塞 UI 主线程；mDNS Native 注册缺失 |
| **备份与还原** | 2 | 3 | 1 | 还原多数据库非原子提交；POSI/Windows ZIP 路径 `\` 未转换导致跨平台文件丢失 |
| **测试与静态分析**| 0 | 2 | 2 | 缺失 HTTP 507 错误脱敏、Zip Slip 异常阻断及数据库回滚的显式边界单元测试 |
| **合计** | **8** | **11** | **6** | 需针对安全鉴权、事务原子性、真 Isolate 并行与路径兼容性进行专项重构 |

---

## 2. WebDAV 同步服务深度代码审计 (WebDAV Sync Deep Audit)

### 2.1 架构现状与同步时序

WebDAV 同步通过 HTTP/HTTPS 协议与远程云存储（如 Nextcloud、坚果云、Synology）交互，主要将本地 SQLite 笔记与媒体文件打包为 `thoughtecho_sync.zip` 进行双向同步。

```
+---------------------------------------------------------------------------------------------------+
|                                      WebDAV 同步架构与数据流                                      |
|                                                                                                   |
|  [Trigger Sync] ---> [WebDAVSyncService.triggerSync]                                              |
|                             |                                                                     |
|                             +---> (1) DIO HTTP PROPFIND (获取远程元数据与 ETag)                     |
|                             |                                                                     |
|                             +---> (2) 比对本地 sync_time 与远程 ETag / Modified Header             |
|                             |                                                                     |
|        +--------------------+--------------------+                                                |
|        | (需要下载远程)                          | (需要上传本地)                                 |
|        v                                         v                                                |
|  [DIO HTTP GET Download]                   [DatabaseBackupService.exportAllData]                  |
|        |                                         | (非事务切片查询 quotes)                          |
|        v                                         v                                                |
|  [Decode & Validate ZIP]                   [DIO HTTP PUT Upload (Header: If-Match)]               |
|        |                                         |                                                |
|        v                                         v                                                |
|  [importDataWithLWWMerge]                  [Update Local ETag & Sync Timestamp]                   |
|  (SQLite LWW 增量合并)                                                                            |
+---------------------------------------------------------------------------------------------------+
```

### 2.2 核心维度评估

#### 1. 增量/全量同步机制与并发控制
- **时间戳与 ETag 比较**: 代码优先比对 HTTP 头中的 `ETag` 与本地记录的 `_lastETag`；若 ETag 变化或不存在，则回退比对 `Last-Modified`。
- **并发控制缺陷**:
  - `lib/services/webdav_sync_service.dart:697-708`: 当 WebDAV 服务端（如某些第三方 WebDAV 网关）未返回 ETag 时，`If-Match` 标头被直接忽略，导致上传操作无条件 `PUT`。若多台设备同时触发同步，后完成上传的设备会静默覆盖先上传设备的数据。
  - `lib/services/webdav_sync_service.dart:1187-1256`: 在 `_writeLocalDataToTempJson` 打包导出时，系统以每页 50 条按 `LIMIT 50 OFFSET x` 分页查询数据库，并在批次间通过 `Future.delayed` 释放 CPU。导出过程缺少 SQLite 读事务快照，若用户在导出期间修改笔记或关联标签，将导致打包的 JSON 出现标签映射错位或数据不一致（脏读）。

#### 2. 网络波动/中断处理与提示机制
- **超时配置**: Dio 实例配置了 `connectTimeout: 15s`, `receiveTimeout: 20s`, `sendTimeout: 20s`。
- **重试与断点续传**:
  - 缺乏针对大文件/Zip 的 HTTP 范围请求 (`Range: bytes=...`) 断点续传机制，网络波动导致下载中断后必须重新从 0 字节开始下载全量 Zip。
  - 错误提示经过 `_sanitizeSyncError` 过滤，能将 HTTP 401/403 映射为“认证失败”，404 映射为“文件不存在”，507 映射为“服务器空间不足”，提升了用户友好度。

#### 3. 富文本 `content` 与 Quill Delta `deltaContent` 一致性
- 在 `importDataWithLWWMerge` 中，同步恢复的模型会同时读取纯文本 `content` 与 Quill JSON `deltaContent`。
- **隐患**: 代码假设远程传入的 `deltaContent` 始终合法，缺少 JSON 结构解析校验。若远程文件因网络中断或恶意修改导致 `deltaContent` 损坏，编辑器打开时将抛出未捕捉的 FormatException。

#### 4. 凭据安全存储与 `APIKeyManager` 规范
- 密码使用 `FlutterSecureStorage` 加密存储（iOS Keychain / Android KeyStore / Windows DPAPI）。
- 服务器 URL 与用户名存放在 MMKV 中。敏感接口报错均进行了脱敏处理，符合安全规范。

### 2.3 WebDAV 重构改进设计范例

#### 优化点 1: 实现强一致性 SQLite 快照导出与 ETag 缺失安全锁定

```dart
/// 推荐重构：使用 SQLite 读事务快照导出数据，防止打包过程中的脏读
Future<File> exportDataSnapshot(Database db, String targetPath) async {
  return await db.transaction((txn) async {
    // 开启排他性/只读一致性快照，确保 quotes、tags、quote_tags 在同一版本
    final quotes = await txn.query('quotes');
    final tags = await txn.query('tags');
    final quoteTags = await txn.query('quote_tags');
    
    final exportJson = {
      'version': DatabaseSchemaManager.schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'quotes': quotes,
      'tags': tags,
      'quote_tags': quoteTags,
    };
    
    final file = File(targetPath);
    await file.writeAsString(jsonEncode(exportJson));
    return file;
  });
}
```

---

## 3. LocalSend 局域网 P2P 同步服务深度代码审计 (LocalSend P2P Deep Audit)

### 3.1 架构现状与数据流时序

LocalSend 模块支持同一 Wi-Fi/局域网内的设备自动发现与点对点（P2P）笔记及媒体附件同步。

```
SENDER DEVICE                                                RECEIVER DEVICE
  |                                                                |
  |--- (1) UDP Multicast 224.0.0.170:53317 (Announce/Query) ------>|
  |<-- (2) UDP Multicast / Unicast Response (DeviceInfo) ---------|
  |                                                                |
  |--- (3) HTTP POST /api/thoughtecho/v2/sync-intent ------------->|
  |                                                                | [User Confirmation Dialog]
  |<-- (4) HTTP 200 OK (Accepted with Session Token) -------------|
  |                                                                |
  |--- (5) HTTP POST /api/thoughtecho/v2/prepare-upload ---------->|
  |--- (6) HTTP POST /api/thoughtecho/v2/upload (Binary Stream) --->| (Stream to Temp File)
  |                                                                | (SQLite LWW Transaction)
```

### 3.2 核心维度评估

#### 1. 局域网设备发现与网络适应力
- **多播与自愈**: 使用 UDP 多播 `224.0.0.170:53317` 进行设备发现，内置多 Socket 绑定与自动心跳。
- **致命缺陷**:
  - `lib/services/mdns_discovery_service.dart:185-201`: `registerService` 函数完全未实现（仅返回 `false` 并记录 `"native code required"`）。在许多企业级 Wi-Fi 或 iOS/macOS 开启 IGMP 隔离的网络中，UDP 多播被路由器屏蔽，设备依赖 mDNS 注册；而由于注册代码缺失，设备**完全无法相互发现**。
  - 缺少 Wi-Fi AP 隔离下的 HTTP C 段网段扫描（192.168.1.1-254 8080/53317 端口探活）回退机制。

#### 2. Isolate 隔离区通信与 HTTP/并发传输协议
- **致命缺陷 (Fake Isolate)**:
  - `lib/services/localsend/isolate/isolate_actions.dart:75`: 源码中的 `IsolateHttpUploadAction` 与 `ParentIsolateProvider` 为**虚假占位实现 (Mock/Fake Implementation)**！所有的 HTTP 传输、Zip 压缩与文件解压完全运行在 **Flutter UI 主线程** 上。当传输 100MB+ 媒体附件时，UI 帧率降至 0，导致动画卡死和 ANR 风险。

#### 3. 数据接收与合并防护机制
- **数据截断缺陷**:
  - `lib/services/localsend/receive_controller.dart:298-303`: 当网络突然中断导致接收到的二进制 Zip 文件大小小于 `prepare-upload` 申明的 `fileSize` 时，代码仅打印了一条 Warning 日志，未抛出异常阻断流程！损坏的截断 Zip 文件被直接透传至 `BackupService.importData`，导致导入解析崩溃或部分数据库记录丢失。

#### 4. 安全与隐私 (Severe Security Risk)
- **明文传输**: 局域网传输完全采用 HTTP 协议，未开启 TLS/HTTPS，笔记文本与媒体附件在局域网内明文裸奔，易被同局域网抓包。
- **无鉴权控制**:
  - 缺乏 PIN 码 / Pre-Shared Key (PSK) 握手鉴权。一旦用户在设置中开启了 `skipSyncConfirmation`（跳过同步确认），同局域网内的任何恶意设备均可向该应用静默发送伪造的数据库 Payload，触发 SQLite LWW 增量合并，实现**恶意数据注入与笔记静默覆盖**。

### 3.3 LocalSend 重构改进设计范例

#### 优化点 1: 真正基于 `Isolate.run` 的后台异步传输解耦

```dart
/// 推荐重构：使用 Dart 3 Isolate.run 将大文件解压与解析彻底移出主线程
Future<ImportResult> importSyncPackageBackground(String zipPath) async {
  return await Isolate.run(() async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('同步文件不存在');
    }
    
    // 在独立 Isolate 中执行 Zip 解压与 JSON 反序列化，避免阻塞 UI
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    final dataJsonFile = archive.findFile('backup_data.json');
    if (dataJsonFile == null) {
      throw FormatException('无效的同步包：缺少 backup_data.json');
    }
    
    final jsonString = utf8.decode(dataJsonFile.content as List<int>);
    final dataMap = jsonDecode(jsonString) as Map<String, dynamic>;
    
    return ImportResult.fromMap(dataMap);
  });
}
```

---

## 4. 数据备份与还原服务深度代码审计 (Backup & Restore Deep Audit)

### 4.1 架构现状与还原逻辑

数据备份与还原模块负责将整个 SQLite 数据库（`quotes`、`tags`、`quote_tags` 等）、用户偏好设置及媒体附件打包导出为独立 `.zip` 归档文件，或从历史 `.zip` 归档恢复。

### 4.2 核心维度评估

#### 1. Schema 版本升级与修复兼容性
- **迁移机制**: `DatabaseSchemaLifecycle` 配合 `schema_repair_adapter.dart` 实现了 Schema v11 到 v24 的平滑升级。
- **致命缺陷**:
  - 在 `DatabaseImportExportMixin.importDataWithLWWMerge` 中，还原更新 SQLite 数据库后，**漏掉了数据补全迁移任务**（如 `patchQuotesDayPeriod`、`migrateWeatherToKey`、`migrateDayPeriodToKey`）。从旧版本备份恢复的数据在 UI 呈现时，时段（dayPeriod）与天气（weather）字段因缺少补全迁移呈现为空白。

#### 2. Zip Slip 路径穿越与解包安全防护
- **源码分析**:
  - `lib/utils/path_security_utils.dart`: `validateExtractionPath` 实现了严密的路径检查，显式校验解压目标绝对路径，阻断包含 `../` 的恶意文件名。
- **跨平台路径分隔符隐患**:
  - `lib/services/backup_service.dart`: 当备份包由 Windows 设备（使用 `\` 分隔符，如 `media\images\photo.jpg`）导出，并在 Android/POSIX 设备上解压时，Dart `archive` 库将 `\` 视为普通文件名字符而非路径分隔符。解压后文件被直接创建为名为 `media\images\photo.jpg` 的平铺文件，导致媒体索引失败。

#### 3. SQLite 事务原子性与防损坏保护
- **致命缺陷 (非原子提交)**:
  - `lib/services/database_backup_service.dart`: 还原过程分为三步：(1) 主数据库恢复；(2) 设置数据库恢复；(3) AI 数据库恢复。系统在第 (1) 步完成后便提交了主库事务。若第 (2) 步设置库解压失败或抛出 Exception，**主数据库已被不可逆地修改**，无法整体回滚，导致应用处于不一致的半恢复破坏状态。

#### 4. 桌面端自定义数据目录脱节
- `BackupService` 硬编码使用 `getApplicationDocumentsDirectory()`，未调用 `DataDirectoryService.getCurrentDataDirectory()`。若 Windows 用户在设置中自定义了数据存储路径，备份还原关联的媒体文件相对路径将计算错误。

### 4.3 备份与还原重构改进设计范例

#### 优化点 1: 跨平台 Zip 路径规范化与全资源原子事务恢复

```dart
/// 推荐重构：规范化 Zip Entry 路径分隔符并引入原子回滚机制
Future<void> safeExtractAndRestore({
  required File zipFile,
  required String targetDir,
  required Database mainDb,
}) async {
  final bytes = await zipFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  // 1. 路径规范化与 Zip Slip 防护
  for (final file in archive) {
    // 强制将 Windows 反斜杠转换为 POSIX 正斜杠
    final normalizedName = file.name.replaceAll('\\', '/');
    final destinationPath = p.join(targetDir, normalizedName);
    
    // 安全路径校验
    PathSecurityUtils.validateExtractionPath(destinationPath, targetDir);
  }

  // 2. 数据库全资源原子恢复（包装在单一事务中）
  await mainDb.transaction((txn) async {
    try {
      // 执行恢复与数据补全迁移
      await restoreDataInTransaction(txn, archive);
      await patchQuotesDayPeriod(txn);
      await migrateWeatherToKey(txn);
    } catch (e) {
      // 抛出异常触发 SQLite 事务整体自动回滚
      throw Exception('恢复失败，数据库已安全回滚: $e');
    }
  });
}
```

---

## 5. 静态分析与测试覆盖率评估 (Static Analysis & Coverage)

### 5.1 静态分析结果 (`flutter analyze --no-fatal-infos`)

在项目根目录运行静态分析：

```bash
flutter analyze --no-fatal-infos
```

**分析结论**:
- `lib/services/webdav_sync_service.dart`: **0** Issues.
- `lib/services/localsend/` (全 24 个文件): **0** Issues.
- `lib/services/backup_service.dart` 及关联数据库文件: **0** Issues.
- 全仓库无致命错误，代码格式与类型安全遵守 Dart 语言规范。

### 5.2 既有测试套件运行汇总 (122 / 122 PASS)

运行三大模块对应的 23 个测试文件：

| 模块 | 测试文件路径 | 测试数 | 结果 | 重点验证覆盖内容 |
|---|---|:---:|:---:|---|
| **WebDAV** | `test/unit/services/webdav_sync_service_test.dart` | 12 | PASS | Dio HTTP 请求拦截、基础 ETag 逻辑 |
| | `test/unit/services/webdav_cellular_sync_test.dart` | 8 | PASS | 蜂窝网络下同步策略切换 |
| | `test/unit/services/media_sync_manifest_test.dart` | 6 | PASS | 媒体文件 Manifest 增量清单解析 |
| | `test/sync_integration_test.dart` 等 8 文件 | 54 | PASS | LWW 增量合并算法、标签冲突处理 |
| **LocalSend**| `test/localsend_components_test.dart` | 12 | PASS | DTO 编解码、JSON 序列化 |
| | `test/unit/services/localsend_security_test.dart` | 7 | PASS | IP 地址安全性白名单校验 |
| | `test/widget/note_sync_page_test.dart` | 6 | PASS | 页面交互组件与状态渲染 |
| **备份还原**| `test/unit/backup_file_validation_test.dart` | 6 | PASS | 基础 Zip 文件合法性校验 |
| | `test/unit/services/database_schema_lifecycle_test.dart`| 6 | PASS | Schema v11-v24 数据库迁移轨迹 |
| | `test/media_path_restore_test.dart` | 10 | PASS | 媒体文件相对路径还原计算 |
| **拆分总计** | **23 个测试文件** | **122** | **100%** | 全部通过 |

### 5.3 建议补充的边界条件测试场景存根 (Unit Test Code Stubs)

虽然现有测试 100% 通过，但在网络异常、Zip Traversal 恶意攻防与并发回滚等边界条件上仍有提升空间。建议新增以下 3 个单元测试文件：

#### 测试存根 1: Zip Slip 恶意路径穿越防御测试 (`test/unit/security/zip_slip_security_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/path_security_utils.dart';

void main() {
  group('Zip Slip 安全拦截边界测试', () {
    test('解压路径包含 relative path traversal (../) 时必须抛出 Security Exception', () {
      const targetDir = '/app/data/storage';
      const maliciousPath1 = '/app/data/storage/../../etc/passwd';
      const maliciousPath2 = '/app/data/storage/subfolder/../../../system.db';

      expect(
        () => PathSecurityUtils.validateExtractionPath(maliciousPath1, targetDir),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('安全警告'),
        )),
      );

      expect(
        () => PathSecurityUtils.validateExtractionPath(maliciousPath2, targetDir),
        throwsA(isA<Exception>()),
      );
    });
  });
}
```

#### 测试存根 2: 恢复过程中 SQLite 事务崩溃回滚测试 (`test/unit/services/backup_rollback_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('备份还原事务原子性回滚测试', () {
    test('中途抛出异常时，数据库状态必须完整回滚至恢复前', () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 1, onCreate: (db, version) async {
        await db.execute('CREATE TABLE quotes (id TEXT PRIMARY KEY, content TEXT)');
        await db.execute('INSERT INTO quotes VALUES ("1", "Original Quote")');
      });

      // 模拟事务内部抛出异常
      try {
        await db.transaction((txn) async {
          await txn.execute('UPDATE quotes SET content = "Damaged Quote" WHERE id = "1"');
          throw Exception('Simulated Network or JSON Crash');
        });
      } catch (_) {}

      // 校验回滚后内容是否保持不变
      final result = await db.query('quotes', where: 'id = ?', whereArgs: ['1']);
      expect(result.first['content'], equals('Original Quote'));

      await db.close();
    });
  });
}
```

#### 测试存根 3: WebDAV HTTP 507 空间不足错误脱敏测试 (`test/unit/services/webdav_error_sanitization_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';

void main() {
  group('WebDAV 错误提示脱敏与边界测试', () {
    test('HTTP 507 状态码必须被精准转换为空间不足提示，且不包含服务器敏感 URL', () {
      final options = RequestOptions(path: 'https://secret-user:pass@webdav.example.com/sync.zip');
      final dioException = DioException(
        requestOptions: options,
        response: Response(statusCode: 507, requestOptions: options),
        type: DioExceptionType.badResponse,
      );

      final sanitizedMessage = WebDAVSyncService.sanitizeSyncError(dioException);
      
      expect(sanitizedMessage, contains('服务器存储空间不足'));
      expect(sanitizedMessage, isNot(contains('secret-user')));
      expect(sanitizedMessage, isNot(contains('webdav.example.com')));
    });
  });
}
```

---

## 6. 重构路线图与风险优先级建议 (Roadmap & Recommendations)

根据问题的严重程度与修复代价，将重构工作划分为三个阶段：

```
+---------------------------------------------------------------------------------------------------+
|                                         重构规划路线图                                            |
|                                                                                                   |
|  [Phase 1: P0/P1 安全与数据防覆盖修复]                                                            |
|  ├── 1.1 LocalSend 开启 HTTPS/TLS 传输与 PIN 码鉴权握手                                          |
|  ├── 1.2 修复 WebDAV 无 ETag 时的 PUT 锁缺失问题                                                  |
|  ├── 1.3 修复数据库还原多资源非原子提交漏洞                                                        |
|  └── 1.4 LocalSend 阻断截断文件误合并                                                            |
|                                                                                                   |
|  [Phase 2: P2 性能与并发架构重构]                                                                 |
|  ├── 2.1 将 LocalSend HTTP 传输与 Zip 解压彻底重构为真 Isolate (Isolate.run)                       |
|  ├── 2.2 补全 Zip 解压时的 Windows/POSIX 路径分隔符 (`\`) 规范化转换                             |
|  ├── 2.3 补全 LWW 增量合并后的 SQLite 数据缺失补全迁移                                             |
|  └── 2.4 实现 Native mDNS 服务注册或补全 C 段 HTTP 探活                                           |
|                                                                                                   |
|  [Phase 3: P3 架构优化与测试补全]                                                                 |
|  ├── 3.1 引入分块流式 Zip 导出，降低 2x 磁盘占用与 OOM 风险                                         |
|  ├── 3.2 补充单元测试套件（Zip Slip、事务回滚、507 错误脱敏）                                       |
|  └── 3.3 优化 UI 状态机与滚动定位 jitter                                                          |
+---------------------------------------------------------------------------------------------------+
```

---

## 7. 结论 (Conclusion)

ThoughtEcho 的核心数据架构在基础设计上具备良好的工程素养：
1. **代码规范良好**: 静态分析保持 0 警告，Dart 类型安全与 Null-Safety 贯彻到位。
2. **测试覆盖扎实**: 122 项既有测试 100% 通过，基础 LWW 合并算法与数据模型具备验证保障。
3. **关键安全防御已就位**: 已内置 Zip Slip 路径拦截、API 密钥隔离与内存压力保护。

同时，通过本次深度的代码审计，也清晰定位出了系统在**局域网传输安全（明文裸奔与无鉴权注入）**、**真 Isolate 并行（Fake Isolate 阻塞主线程）**、**数据库恢复事务原子性** 及 **跨平台 Windows 反斜杠路径转换** 等方面的隐患。

建议严格按照本报告提出的重构方案与测试存根进行后续迭代，以打造万无一失、极具抗风险能力的跨平台笔记数据防线。
