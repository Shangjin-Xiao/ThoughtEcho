# 地图选点 & 笔记地图回忆 实现方案

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为笔记补上精确地点语义，并在后续把这些位置数据用于“地图回忆”视图。这里是地图产品线的实现方案，不负责统一 AI 容器本身。

**Architecture:** 分两阶段实施。Phase 1 实现地图选点 + 选点反向地理编码 + 受控 POI 搜索 + 笔记显示精确地址；Phase 2 实现地图视图页面。两阶段共享同一数据模型（Quote 新增 `poiName` 字段存储用户选择的精确地点名称）。地图 SDK 使用 `flutter_map`（基于 OpenStreetMap，免费无 API Key，与现有 Nominatim 地理编码一致）。

**Tech Stack:** Flutter 3.x, flutter_map + latlong2, Nominatim API (已有), SQLite (sqflite), Provider

## 文档边界

本方案负责：

- `Quote.poiName` 与位置展示语义
- 地图选点页
- 受控 POI 搜索
- 笔记地图回忆页
- 与 Explore 的入口衔接

本方案不负责：

- AI 会话持久化
- Agent 工具运行时
- `/` 命令和统一 AI 交互细节

相关文档：

- `2026-03-28-master-refactoring-explore-page-and-ai-ide.md`
- `2026-03-28-global-ai-ide-and-agent-design.md`
- `2026-03-26-ai-chat-history-and-agent-design.md`

---

## 架构师审查反馈（已采纳）

1. **`poiName` 字段设计 ✅** — 独立字段是对的，但不应混入 `hasLocation` 语义，改用 `hasDisplayLocation` / `primaryLocationLabel` getter
2. **Nominatim POI 限制 ⚠️** — 公共 Nominatim 不适合做 autocomplete 和高频 nearby 搜索。Phase 1 改为：拖图后仅 reverse geocode 一次 + 用户主动提交搜索
3. **POI 搜索抽象 ✅** — 抽出 `PlaceSearchService` 接口，未来可替换为高德/腾讯
4. **数据库迁移 guardrail ✅** — `_removeTagIdsColumnSafely` 的表重建 SQL 必须同步带上 `poi_name`
5. **copyWith 清空语义 ✅** — 保留现有 `??` 写法，UI 层移除 POI 时同时清 location toggle
6. **OSM Tile server ✅** — 需使用合法 tile provider 并做 attribution
7. **Phase 2 clustering ✅** — 默认开启 clustering，无需阈值判断；使用轻量 DTO 而非完整 Quote

---

## 现状分析

### 已有能力
- `Quote` 模型已有 `location`（格式化地址字符串 "国家,省份,城市,区县"）、`latitude`、`longitude` 字段
- `LocationService` 已支持 GPS 定位、Nominatim 反向地理编码、城市搜索
- `LocalGeocodingService` 已支持系统 SDK + 缓存的反向地理编码
- 笔记卡片右上角已显示位置（`formatLocationForDisplay` → "城市·区县"）
- `main` 基线的数据库 schema 还是 version 19，但当前工作区已存在升到 20 的并行改动；地图字段迁移必须使用目标分支上的下一个可用版本号

### 需新增
1. **`poiName` 字段**：存储用户手动选择的精确地点名称（如"故宫博物院""西湖音乐喷泉"）
2. **地图选点页面**：展示当前位置 + 附近 POI 列表 + 搜索 POI
3. **笔记卡片显示逻辑**：优先显示 `poiName`，其次显示 `formatLocationForDisplay`
4. **Phase 2：笔记地图页面**：在地图上以 marker/cluster 展示所有有坐标的笔记

---

## Phase 1: 地图选点功能

### Task 1: 添加 flutter_map 依赖

**Files:**
- Modify: `pubspec.yaml`

**Step 1: 添加依赖**

在 `pubspec.yaml` 的 `dependencies` 中添加：
```yaml
flutter_map: ^7.0.2       # OpenStreetMap 地图组件
latlong2: ^0.9.1           # 经纬度坐标库（flutter_map 依赖）
```

**Step 2: 安装依赖**

Run: `flutter pub get`
Expected: 成功安装，无版本冲突

**Step 3: Commit**
```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: add flutter_map and latlong2 for map location picker"
```

---

### Task 2: Quote 模型新增 `poiName` 字段

**Files:**
- Modify: `lib/models/quote_model.dart`
- Modify: `lib/services/database_schema_manager.dart`

**Step 1: 修改 Quote 模型**

在 `quote_model.dart` 中：

1. 添加字段（在 `longitude` 和 `weather` 之间）：
```dart
final String? poiName; // 用户选择的精确地点名称（如"故宫博物院"）
```

2. 构造函数添加参数：
```dart
this.poiName,
```

3. `Quote.validated` 工厂方法添加参数 `String? poiName`，传递到 `Quote()` 构造函数

4. `fromJson` 中添加：
```dart
poiName: json['poi_name']?.toString(),
```

5. `toJson` 中添加：
```dart
'poi_name': poiName,
```

6. `copyWith` 中添加参数和传递：
```dart
String? poiName,
// ...
poiName: poiName ?? this.poiName,
```

7. 添加 getter：
```dart
bool get hasPoiName => poiName != null && poiName!.isNotEmpty;
```

8. 新增显示语义 getter，但**不要**修改现有 `hasLocation` 的含义：
```dart
bool get hasDisplayLocation =>
    hasPoiName || (location != null && location!.isNotEmpty);
```

说明：`hasLocation` 现在被 UI 用来表示“有地址或坐标”，不应因为新增 `poiName` 改变既有语义；展示优先级由 UI 层按 `poiName > formatLocationForDisplay(location) > coordinates` 决定。

**Step 2: 数据库 schema 升级**

在 `database_schema_manager.dart` 中：

1. 版本号升级到目标分支上的下一个可用值（若 AI 聊天迁移尚未占用，则可为 20；否则顺延）
2. `CREATE TABLE quotes` 中 `longitude REAL,` 后添加 `poi_name TEXT,`
3. `upgradeDatabase` 方法中添加对应版本迁移（以下仍以 `20` 为示例）：
```dart
if (oldVersion < 20) {
  await db.execute('ALTER TABLE quotes ADD COLUMN poi_name TEXT');
}
```
4. `_removeTagIdsColumn` 中的 `CREATE TABLE quotes_new` 也要加入 `poi_name TEXT,`（保持一致）

**Step 3: 验证**

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**
```bash
git add lib/models/quote_model.dart lib/services/database_schema_manager.dart
git commit -m "feat: add poiName field to Quote model and database schema v20"
```

---

### Task 3: 抽出 PlaceSearchService，避免把 POI 逻辑塞进 LocationService

**Files:**
- Create: `lib/services/place_search_service.dart`

**Step 1: 添加 POI 数据模型和搜索抽象**

在 `place_search_service.dart` 中定义：
```dart
/// 附近地点（POI）信息
class PoiInfo {
  final String name;       // 地点名称（如"星巴克(天河路店)"）
  final String? address;   // 街道地址
  final String? category;  // 类别（如 restaurant, tourism 等）
  final double lat;
  final double lon;
  final double? distanceMeters; // 距当前位置的距离（米）

  PoiInfo({
    required this.name,
    this.address,
    this.category,
    required this.lat,
    required this.lon,
    this.distanceMeters,
  });
}

abstract class PlaceSearchService {
  Future<List<PoiInfo>> searchNearby(
    double lat,
    double lon, {
    String? query,
    int limit = 20,
  });

  Future<PoiInfo?> reverseSelectedPoint(double lat, double lon);
}
```

**Step 2: 提供 Nominatim 实现，但遵守低频使用约束**

在同文件中实现 `NominatimPlaceSearchService`：
```dart
class NominatimPlaceSearchService implements PlaceSearchService {
  @override
  Future<List<PoiInfo>> searchNearby(
  double lat,
  double lon, {
    String? query,
    int limit = 20,
  }) async {
    // 仅在用户主动搜索时调用 search API
  }

  @override
  Future<PoiInfo?> reverseSelectedPoint(double lat, double lon) async {
    // 地图拖动稳定后，只做一次 reverse geocode
  }
}
```

具体实现：
- 有 query 时调用 `https://nominatim.openstreetmap.org/search?q={query}&format=json&addressdetails=1&limit={limit}&viewbox={bbox}&bounded=1`
- 无 query 时不要自动刷 nearby 列表；只调用 `reverse` 获取当前选点的地址/POI 候选
- 计算与当前位置的距离（使用 Haversine 公式或 `Geolocator.distanceBetween`）
- 按距离排序

`LocationService` 继续只负责设备定位、坐标缓存和地址格式化，不承担 POI 搜索职责。

**Step 3: 验证**

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**
```bash
git add lib/services/place_search_service.dart
git commit -m "feat: add PlaceSearchService for map POI lookup"
```

---

### Task 4: 创建地图选点页面

**Files:**
- Create: `lib/pages/map_location_picker_page.dart`

**Step 1: 实现地图选点页面**

页面结构：
```
┌────────────────────────────────┐
│ AppBar: "选择位置"    [搜索] [✓] │
├────────────────────────────────┤
│                                │
│    flutter_map 地图组件          │
│    (中心 marker + 当前位置)      │
│                                │
├────────────────────────────────┤
│ ┌─ 当前位置 ──────────────────┐ │
│ │ 📍 当前: 广州市·天河区       │ │
│ └────────────────────────────┘ │
│ ┌─ 附近地点 ──────────────────┐ │
│ │ 🏪 星巴克(天河路店)   200m   │ │
│ │ 🏨 正佳广场          350m   │ │
│ │ 🌳 天河公园          500m   │ │
│ │ ...                        │ │
│ └────────────────────────────┘ │
└────────────────────────────────┘
```

功能要求：
- 使用 `flutter_map` + OpenStreetMap tiles 显示地图
- 初始位置为当前 GPS 坐标或传入的 `initialLatitude/initialLongitude`
- 地图中心有一个固定 pin marker
- 拖动地图时更新中心坐标，防抖 800-1000ms 后只做一次 reverse geocode，更新“当前选点”信息
- 顶部搜索按钮打开搜索框，用户主动输入关键词时才触发 POI 搜索
- 底部列表显示“当前选点” + 最近一次主动搜索得到的 POI，点击选择
- "当前位置" 选项始终在列表顶部（不选择具体 POI，只用当前城市级地址）
- 点击确认后返回 `MapPickerResult`:
```dart
class MapPickerResult {
  final double latitude;
  final double longitude;
  final String? poiName;          // 选择的 POI 名称
  final String? formattedAddress; // 格式化地址字符串
}
```

- 页面需国际化：所有 UI 文案通过 l10n
- 支持 Material 3 主题
- 文件控制在 400 行以内（如超出则拆分为 `map_picker/` 子目录）

**Step 2: 添加 l10n 文案**

在 `lib/l10n/app_zh.arb` 和 `lib/l10n/app_en.arb` 中添加：
```json
"mapPickerTitle": "选择位置",
"mapPickerCurrentLocation": "当前位置",
"mapPickerNearbyPlaces": "附近地点",
"mapPickerSearchHint": "搜索地点",
"mapPickerNoResults": "未找到附近地点",
"mapPickerLoading": "正在搜索附近地点...",
"mapPickerConfirm": "确认选择",
"mapPickerDistanceMeters": "{distance}m",
"mapPickerDistanceKm": "{distance}km"
```

**Step 3: 运行 l10n 生成**

Run: `flutter gen-l10n`
Expected: 生成成功

**Step 4: 验证**

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 5: Commit**
```bash
git add lib/pages/map_location_picker_page.dart lib/l10n/
git commit -m "feat: add map location picker page with POI search"
```

---

### Task 5: 集成地图选点到笔记编辑器

**Files:**
- Modify: `lib/pages/note_editor/editor_metadata_location_section.dart`
- Modify: `lib/pages/note_editor/editor_location_dialogs.dart`
- Modify: `lib/pages/note_editor/editor_location_fetch.dart`
- Modify: `lib/pages/note_full_editor_page.dart` (添加 `_poiName` 状态变量)

**Step 1: 添加 _poiName 状态变量**

在 `note_full_editor_page.dart` 中：
- 添加 `String? _poiName;` 状态变量（在 `_location` 附近）
- 添加 `String? _originalPoiName;` 用于变更检测
- 在 `initState` 中从 `widget.initialQuote?.poiName` 初始化
- 在保存逻辑中传递 `poiName` 到 `Quote` 构造

**交互变更（2026-03-31 确认）：**
- **不新增按钮**，复用编辑器现有位置按钮
- **单击**：保持现有行为（开启/关闭 GPS 定位 toggle）
- **长按**：打开 `MapLocationPickerPage`；无论是否已有坐标，只要定位服务可用就打开地图；无坐标时先自动 GPS 定位再以当前位置为地图中心
- 选完 POI 后位置区域主行显示 POI 名称，小字显示城市·区县
- 清除 POI 在编辑位置对话框中操作

**Step 2: 修改位置 section UI**

在 `editor_metadata_location_section.dart` 中：
- 位置按钮包裹 `GestureDetector`，`onLongPress` 打开 `MapLocationPickerPage`
- 返回 `MapPickerResult` 后更新 `_poiName`, `_latitude`, `_longitude`, `_location`
- 位置显示优先使用 `_poiName`（如果有），格式："POI名称"
- 已有 POI 时显示 POI 名称 + 小字显示城市·区县
- 原有仅地址/仅坐标逻辑保持可用，避免无 POI 时退化

**Step 3: 修改编辑模式对话框**

在 `editor_location_dialogs.dart` 中：
- 对话框中新增"更换地点"选项，点击后打开地图选点页面
- 有 `poiName` 时显示 POI 名称

**Step 4: 验证**

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 5: Commit**
```bash
git add lib/pages/note_full_editor_page.dart lib/pages/note_editor/
git commit -m "feat: integrate map location picker into note editor"
```

---

### Task 6: 集成地图选点到快速笔记对话框

**Files:**
- Modify: `lib/widgets/add_note_dialog.dart`

**Step 1: 添加 _poiName 状态变量和地图入口**

- 添加 `String? _newPoiName;` 和 `String? _originalPoiName;` 状态变量
- 在位置相关 UI 区域添加"选择精确位置"入口
- 保存时将 `_newPoiName ?? _originalPoiName` 传入 Quote

**Step 2: 验证**

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 3: Commit**
```bash
git add lib/widgets/add_note_dialog.dart
git commit -m "feat: integrate map location picker into quick add note dialog"
```

---

### Task 7: 笔记卡片显示优先使用 POI 名称

**Files:**
- Modify: `lib/widgets/quote_item_widget.dart` (约 L316-L341)

**Step 1: 修改显示逻辑**

在 `quote_item_widget.dart` 的位置显示区域（约 L320-L340），修改 `Text` widget 的内容：

```dart
// 显示优先级：poiName > formatLocationForDisplay > coordinates
(quote.hasPoiName)
    ? quote.poiName!
    : (quote.location != null &&
            LocationService.formatLocationForDisplay(quote.location).isNotEmpty)
        ? LocationService.formatLocationForDisplay(quote.location)
        : LocationService.formatCoordinates(quote.latitude, quote.longitude),
```

同时把外围判定从 `quote.hasLocation` 改为更贴近展示语义的判断，例如 `quote.hasDisplayLocation || quote.hasCoordinates`，避免因为保留旧 `hasLocation` 含义而漏显 `poiName`。

**Step 2: 验证**

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 3: Commit**
```bash
git add lib/widgets/quote_item_widget.dart
git commit -m "feat: prioritize POI name display on note cards"
```

---

### Task 8: 备份恢复兼容性

**Files:**
- Verify: `lib/services/backup_service.dart`（检查 `poi_name` 字段是否自动兼容）

**Step 1: 检查备份恢复逻辑**

由于 `Quote.toJson()` / `Quote.fromJson()` 已经包含 `poi_name` 字段，且数据库 schema 已更新，需要确认：
- 备份导出 JSON 包含 `poi_name`
- 恢复导入时 `poi_name` 正确解析（`fromJson` 已处理）
- 旧版本备份文件（无 `poi_name`）导入时不会出错（`?.toString()` 返回 null）

通常无需修改代码，但需验证。

**Step 2: Commit（如有修改）**

---

### Task 9: 单元测试

**Files:**
- Modify: 相关测试文件

**Step 1: Quote 模型测试**

确认现有 `quote_model_test.dart` 覆盖 `poiName` 字段的序列化/反序列化：
- `toJson()` 包含 `poi_name`
- `fromJson()` 正确解析 `poi_name`
- `copyWith(poiName: ...)` 工作正常
- `hasPoiName` getter 返回正确值
- `hasLocation` 在只有 `poiName` 时返回 true

**Step 2: 运行测试**

Run: `flutter test test/unit/models/quote_model_test.dart`
Expected: 全部通过

**Step 3: Commit**
```bash
git add test/
git commit -m "test: add poiName field tests for Quote model"
```

---

## Phase 2: 笔记地图回忆（后续实施，此处仅列出架构设计）

### 设计概要

#### 数据查询
在 `DatabaseService` / `database_query_mixin.dart` 中添加方法：
```dart
class QuoteMapPoint {
  final String id;
  final String contentPreview;
  final String date;
  final double latitude;
  final double longitude;
  final String? location;
  final String? poiName;
}

/// 获取所有有坐标的笔记（用于地图展示）
/// 返回轻量 DTO（不含 deltaContent 等大字段）
Future<List<QuoteMapPoint>> getQuotesWithCoordinates({
  String? startDate,
  String? endDate,
}) async {
  // SELECT id, content, date, latitude, longitude, location, poi_name, ...
  // WHERE latitude IS NOT NULL AND longitude IS NOT NULL
  // ORDER BY date DESC
}
```

#### 地图页面
- 新建 `lib/pages/note_map_page.dart`
- 使用 `flutter_map` 全屏展示地图
- 使用 marker clustering（`flutter_map_marker_cluster` 插件）避免 marker 重叠
- 每个 marker 点击弹出笔记预览卡片（显示内容摘要 + 日期 + POI 名称）
- 底部可切换时间范围筛选

#### 入口
- 在首页或记录页添加"地图回忆"入口按钮（`Icons.map_outlined`）
- 也可在笔记详情页点击位置跳转到地图视图

#### 性能考虑
- 默认启用 marker clustering，而不是达到某个阈值后再切换
- 仅加载可视区域内的 marker
- 使用 `RepaintBoundary` 包裹地图组件

---

## 技术决策记录

| 决策 | 理由 |
|------|------|
| 使用 `flutter_map` 而非 Google Maps | 免费无 API Key；与现有 Nominatim 生态一致；OpenStreetMap 在中国可用性比 Google Maps 好 |
| 新增 `poiName` 字段而非复用 `location` | `location` 存储"国家,省份,城市,区县"格式化结构，用于城市级展示；`poiName` 存储用户选择的精确地点，职责分离 |
| Nominatim 搜索 POI 而非专用 POI API | 避免引入新的 API 依赖和 Key 管理；Nominatim 已在项目中使用；POI 精度满足笔记场景需求 |
| Phase 2 使用 marker clustering | 大量 marker 会严重影响地图性能；clustering 是标准解决方案 |

---

## 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| Nominatim POI 数据不够丰富（尤其中国） | 搜索功能作为补充；"当前位置"始终可用作 fallback |
| OpenStreetMap 瓦片在某些地区加载慢 | 可配置多个 tile server；考虑添加 tile 缓存 |
| flutter_map 在 Web 平台的兼容性 | flutter_map 原生支持 Web；需测试确认 |
| 数据库升级版本号冲突 | AI 聊天与地图规划都不要硬编码 `v20`；真正实施前以目标分支最新 schema 为准 |
| Nominatim 速率限制（1 request/second） | 搜索加防抖（500ms）；缓存搜索结果 |

---

## 依赖关系

```
Task 1 (flutter_map 依赖)
  └─> Task 4 (地图选点页面)
       └─> Task 5 (集成到编辑器)
       └─> Task 6 (集成到快速对话框)

Task 2 (Quote 模型 + DB schema)
  └─> Task 3 (POI 搜索)
  └─> Task 5 (集成到编辑器)
  └─> Task 6 (集成到快速对话框)
  └─> Task 7 (卡片显示)
  └─> Task 8 (备份兼容)
  └─> Task 9 (测试)

可并行：Task 1 + Task 2 + Task 3
可并行：Task 5 + Task 6 + Task 7（均依赖 Task 2 和 Task 4）
```
