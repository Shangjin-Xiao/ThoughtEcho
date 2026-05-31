# WebDAV Cellular Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement WebDAV cellular data synchronization controls, allowing users to disable sync on cellular networks, or optionally sync only text notes and skip large media attachments to save data.

**Architecture:** Integrate the `connectivity_plus` package inside `ConnectivityService` to detect cellular networks. Extend `WebDAVSyncService` with settings stored in MMKV for cellular synchronization policies (`syncOnCellular`, `syncNotesOnlyOnCellular`). Respect these settings inside the WebDAV sync workflow (`triggerSync`), and expose them in the WebDAV configuration UI (`webdav_sync_page.dart`) with responsive design and clean descriptions.

**Tech Stack:** Flutter, Dart, MMKV, Provider, connectivity_plus

---

### Task 1: Update l10n Files for Cellular Sync Settings

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`

**Step 1: Write localized strings for Chinese (zh)**
Add the following keys to `lib/l10n/app_zh.arb` before the closing brace:
```json
  "webdavSyncOnCellular": "允许数据流量下同步",
  "webdavSyncOnCellularSubtitle": "允许在移动数据网络下进行云端备份 and 合并",
  "webdavSyncNotesOnlyOnCellular": "数据流量下仅同步笔记",
  "webdavSyncNotesOnlyOnCellularSubtitle": "启用后在移动网络下仅同步文本，跳过大型媒体文件以节省流量",
```

**Step 2: Write localized strings for English (en)**
Add the following keys to `lib/l10n/app_en.arb` before the closing brace:
```json
  "webdavSyncOnCellular": "Sync over cellular data",
  "webdavSyncOnCellularSubtitle": "Allow cloud backup and merge under mobile data networks",
  "webdavSyncNotesOnlyOnCellular": "Sync notes only on cellular",
  "webdavSyncNotesOnlyOnCellularSubtitle": "Only sync lightweight text notes and skip heavy media files to save data",
```

**Step 3: Run `flutter gen-l10n` to regenerate internationalization classes**
Run: `flutter gen-l10n`
Expected: Successful build without errors.

**Step 4: Commit**
```bash
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb
git commit -m "l10n: add localization strings for cellular sync settings"
```

---

### Task 2: Implement Cellular Detection in ConnectivityService

**Files:**
- Modify: `lib/services/connectivity_service.dart`

**Step 1: Write minimal code to detect cellular network**
Import `connectivity_plus` and define `isCellularConnection()` inside `ConnectivityService`:
```dart
import 'package:connectivity_plus/connectivity_plus.dart';

// Inside class ConnectivityService
  /// 检查当前是否为移动数据流量连接
  Future<bool> isCellularConnection() async {
    try {
      final List<ConnectivityResult> results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.mobile);
    } catch (e) {
      logDebug('检查移动数据网络失败: $e');
      return false;
    }
  }
```

**Step 2: Verify compilation**
Run: `flutter analyze`
Expected: Analysis passes with no errors.

**Step 3: Commit**
```bash
git add lib/services/connectivity_service.dart
git commit -m "feat: add cellular connection check in ConnectivityService"
```

---

### Task 3: Extend WebDAVSyncService with Cellular Sync Configurations and Workflow

**Files:**
- Modify: `lib/services/webdav_sync_service.dart`

**Step 1: Add new fields and getters inside `WebDAVSyncService`**
```dart
  bool _syncOnCellular = false;
  bool _syncNotesOnlyOnCellular = false;

  bool get syncOnCellular => _syncOnCellular;
  bool get syncNotesOnlyOnCellular => _syncNotesOnlyOnCellular;
```

**Step 2: Update `_initSettings()` to read keys from MMKV**
```dart
    _syncOnCellular = _mmkv.getBool('webdav_sync_on_cellular') ?? false;
    _syncNotesOnlyOnCellular = _mmkv.getBool('webdav_sync_notes_only_on_cellular') ?? false;
```

**Step 3: Update `saveSettings()` to accept and save new configurations**
Update signature and implementation:
```dart
  Future<void> saveSettings({
    required bool enabled,
    required String provider,
    required String url,
    required String username,
    String? password,
    required bool syncOnLaunch,
    required bool syncOnChange,
    required bool syncOnCellular,
    required bool syncNotesOnlyOnCellular,
  }) async {
    _enabled = enabled;
    _provider = provider;
    _url = url.trim();
    if (_enabled &&
        _url.isNotEmpty &&
        !_url.toLowerCase().startsWith('https://')) {
      throw Exception('HTTPS is required to protect WebDAV credentials');
    }
    if (!_url.endsWith('/')) _url = '$_url/';
    _username = username.trim();
    _syncOnLaunch = syncOnLaunch;
    _syncOnChange = syncOnChange;
    _syncOnCellular = syncOnCellular;
    _syncNotesOnlyOnCellular = syncNotesOnlyOnCellular;

    await _mmkv.setBool('webdav_enabled', _enabled);
    await _mmkv.setString('webdav_provider', _provider);
    await _mmkv.setString('webdav_url', _url);
    await _mmkv.setString('webdav_username', _username);
    await _mmkv.setBool('webdav_sync_on_launch', _syncOnLaunch);
    await _mmkv.setBool('webdav_sync_on_change', _syncOnChange);
    await _mmkv.setBool('webdav_sync_on_cellular', _syncOnCellular);
    await _mmkv.setBool('webdav_sync_notes_only_on_cellular', _syncNotesOnlyOnCellular);

    if (password != null) {
      await _secureStorage.write(
        key: 'webdav_password',
        value: password.trim(),
      );
    }

    notifyListeners();
  }
```

**Step 4: Update `triggerSync` workflow to check cellular status and skip synchronization or media files**
Modify `triggerSync({bool isBackground = false})`:
```dart
    // 移动数据网络检测与过滤策略
    final isCellular = await ConnectivityService().isCellularConnection();
    bool skipMedia = false;
    if (isCellular) {
      if (!_syncOnCellular) {
        if (_syncNotesOnlyOnCellular) {
          logInfo('当前处于移动数据网络下且启用“仅同步笔记”，将跳过大媒体文件同步');
          skipMedia = true;
        } else {
          logInfo('当前处于移动数据网络下且未允许流量同步，跳过 WebDAV 同步');
          return;
        }
      }
    }
```
And wrap the `_syncMediaFiles(dio);` call:
```dart
      // 5. 增量比对并同步大媒体附件 (Images, Videos, Audios)
      if (skipMedia) {
        logDebug('数据流量下跳过大媒体文件同步');
      } else {
        logDebug('开始同步本地与云端媒体文件...');
        await _syncMediaFiles(dio);
      }
```

**Step 5: Verify build**
Run: `flutter analyze`
Expected: Analysis passes.

**Step 6: Commit**
```bash
git add lib/services/webdav_sync_service.dart
git commit -m "feat: integrate cellular sync restrictions in WebDAVSyncService"
```

---

### Task 4: Update WebDAV Sync UI Settings

**Files:**
- Modify: `lib/pages/webdav_sync_page.dart`

**Step 1: Update existing call sites of `saveSettings` to include the two new settings**
Provide `syncService.syncOnCellular` and `syncService.syncNotesOnlyOnCellular` to existing `saveSettings` calls in `_saveAndSync` and the turn-off button.

**Step 2: Add two SwitchListTiles in the Settings Strategy Card**
Inside the column of the Settings Strategy card, add:
```dart
                        const Divider(height: 1),
                        SwitchListTile(
                          title: Text(l10n.webdavSyncOnCellular),
                          subtitle: Text(l10n.webdavSyncOnCellularSubtitle),
                          value: syncService.syncOnCellular,
                          onChanged: (val) {
                            syncService.saveSettings(
                              enabled: syncService.enabled,
                              provider: _selectedProvider,
                              url: _urlController.text,
                              username: _usernameController.text,
                              syncOnLaunch: syncService.syncOnLaunch,
                              syncOnChange: syncService.syncOnChange,
                              syncOnCellular: val,
                              syncNotesOnlyOnCellular: syncService.syncNotesOnlyOnCellular,
                            );
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: Text(l10n.webdavSyncNotesOnlyOnCellular),
                          subtitle: Text(l10n.webdavSyncNotesOnlyOnCellularSubtitle),
                          value: syncService.syncNotesOnlyOnCellular,
                          onChanged: syncService.syncOnCellular
                              ? null // If full sync is allowed on cellular, note-only toggle is disabled (irrelevant)
                              : (val) {
                                  syncService.saveSettings(
                                    enabled: syncService.enabled,
                                    provider: _selectedProvider,
                                    url: _urlController.text,
                                    username: _usernameController.text,
                                    syncOnLaunch: syncService.syncOnLaunch,
                                    syncOnChange: syncService.syncOnChange,
                                    syncOnCellular: syncService.syncOnCellular,
                                    syncNotesOnlyOnCellular: val,
                                  );
                                },
                        ),
```

**Step 3: Verify execution and run tests**
Run: `flutter analyze`
Expected: Zero issues found.

**Step 4: Commit**
```bash
git add lib/pages/webdav_sync_page.dart
git commit -m "feat: expose cellular sync settings in WebDAVSyncPage"
```

---

### Task 5: Write Unit and Widget Tests for Cellular Sync

**Files:**
- Create: `test/unit/services/webdav_cellular_sync_test.dart`

**Step 1: Write unit tests verifying that WebDAVSyncService checks cellular network and acts accordingly**
Mock `ConnectivityService` or use test setups to verify:
- When on cellular network and both settings are false, sync is skipped.
- When on cellular network and `syncNotesOnlyOnCellular` is true, sync continues but media files are skipped.
- When on cellular network and `syncOnCellular` is true, full sync continues.

**Step 2: Run tests and ensure they pass**
Run: `flutter test test/unit/services/webdav_cellular_sync_test.dart`
Expected: Tests pass successfully.

**Step 3: Commit**
```bash
git add test/unit/services/webdav_cellular_sync_test.dart
git commit -m "test: add unit tests for cellular webdav sync policies"
```
