# 执行整合补充 — 2026-03-30 代码审查后变更记录

> 本文档记录了在实际代码审查后，对原 4 份计划的补充和变更，作为实施的最终参考。

## 一、Schema 版本协调

**当前状态：** `main` 分支 schema 版本为 **19**。`feature/recycle-bin-v20` 是独立分支，尚未合并。

**决策：** 本轮重构从 `main` 新建分支，使用以下版本分配：

| 版本 | 内容 |
|------|------|
| v20 | `poi_name TEXT` 字段 + `chat_sessions` 表 + `chat_messages` 表（合并为同一个 migration） |

**理由：** 将 poiName 和聊天表放入同一个 migration，减少版本碎片。两者无依赖冲突，可安全合并。回收站 v20 在独立分支上，未来合并时把回收站改为 v21。

---

## 二、ChatMessage 双定义消除

**发现：**
- `lib/models/chat_message.dart`（32 行）— 独立 ChatMessage 类
- `lib/models/chat_session.dart`（115 行）— 内联 ChatMessage 类
- 两份定义结构相同，但都没被任何其他文件 import

**变更：**
- **保留** `lib/models/chat_message.dart` 作为单一定义源，扩展字段（`role`, `includedInContext`, `toMap`, `fromMap`）
- **修改** `lib/models/chat_session.dart`：删除内联 ChatMessage，改为 `import 'chat_message.dart'`；新增 `sessionType`, `noteId` 可空, `toMap`/`fromMap`

---

## 三、AIService.streamAskQuestion 改造细节

**当前签名：** `Stream<String> streamAskQuestion(Quote quote, String question)`

**当前实现（L1211）：** 调用 `_requestHelper.makeStreamRequestWithProvider()`，这个方法接收 `systemPrompt` + `userMessage` 字符串，内部调用 `createMessages()` 生成 `[system, user]` 两条消息。

**变更方案：** 不直接改 `makeStreamRequestWithProvider` 的签名（避免影响其他调用处），而是：
1. 在 `streamAskQuestion` 内部自行构建 `messages` 列表
2. 使用 `_requestHelper.createRequestBody(messages: ...)` 构建 body
3. 直接调用 `AINetworkManager.makeStreamRequest(url, data: body, ...)` 发送

这与计划文档 Task 1.6 的 Step 3 一致。

---

## 四、`_removeTagIdsColumnSafely` 中 poi_name 同步

**发现：** `_removeTagIdsColumnSafely`（L759-857）通过"创建新表→复制数据→删除旧表→重命名"来删除 `tag_ids` 列。新表 `quotes_new` 的 CREATE TABLE 列出了所有字段。

**变更：** 在 `quotes_new` CREATE TABLE 和 INSERT INTO 中加入 `poi_name TEXT`，避免表重建时丢失新字段。虽然 `_removeTagIdsColumnSafely` 仅在 v12 升级时调用（v12 < v20），不太可能在 v20 之后再触发，但 `cleanupLegacyTagIdsColumn` 可能在 onOpen 时调用，必须保持一致。

---

## 五、flutter_map 依赖确认

**当前 pubspec.yaml：** 无 `flutter_map` 和 `latlong2`。需要新增：
```yaml
flutter_map: ^7.0.2
latlong2: ^0.9.1
```

已有包：`flutter_chat_ui: ^2.9.1`, `flutter_chat_core: ^2.8.0`, `flutter_chat_types: ^3.6.2`, `geolocator: ^14.0.2`, `geocoding: ^4.0.0`

---

## 六、实施顺序（按依赖拓扑排序）

### Phase A — 基建层（无 UI，纯数据/服务）

| 步骤 | 文件 | 内容 |
|------|------|------|
| A1 | `pubspec.yaml` | 添加 `flutter_map` + `latlong2` |
| A2 | `lib/models/chat_message.dart` | 扩展 ChatMessage：role, includedInContext, toMap, fromMap, copyWith |
| A3 | `lib/models/chat_session.dart` | 重写：import ChatMessage, 加 sessionType/noteId 可空/toMap/fromMap |
| A4 | `lib/models/quote_model.dart` | 加 `poiName` 字段全套 |
| A5 | `lib/services/database_schema_manager.dart` | v20 migration: poi_name + chat_sessions + chat_messages + _removeTagIdsColumnSafely 同步 |
| A6 | `lib/services/chat_session_service.dart` | 新建 ChatSessionService |
| A7 | `lib/services/place_search_service.dart` | 新建 PlaceSearchService + NominatimPlaceSearchService |
| A8 | `lib/utils/ai_request_helper.dart` | 新增 createMessagesWithHistory() |
| A9 | `lib/services/ai_service.dart` | streamAskQuestion 加 history 参数 |
| A10 | `lib/main.dart` | 注入 ChatSessionService + PlaceSearchService |
| A11 | `lib/l10n/app_zh.arb` + `app_en.arb` | 新增所有 l10n key（chat + map） |

### Phase B — 页面层

| 步骤 | 文件 | 内容 |
|------|------|------|
| B1 | `lib/pages/note_qa_chat_page.dart` | 重写：持久化 + 多轮 + 会话切换 |
| B2 | `lib/pages/map_location_picker_page.dart` | 新建地图选点页面 |
| B3 | `lib/pages/note_editor/*` | 集成地图选点到编辑器 |
| B4 | `lib/widgets/add_note_dialog.dart` | 集成地图选点到快速添加 |
| B5 | `lib/widgets/quote_item_widget.dart` | poiName 显示优先级 |

### Phase C — Agent 框架（Phase 2 of AI plan）

| 步骤 | 文件 | 内容 |
|------|------|------|
| C1 | `lib/services/agent_tool.dart` | AgentTool 接口 |
| C2 | `lib/services/agent_tools/` | 首批工具（NoteSearchTool, NoteStatsTool, WebSearchTool） |
| C3 | `lib/services/agent_service.dart` | Agent 运行时 + 工具循环 |
| C4 | `lib/pages/agent_chat_page.dart` | Agent 对话页面 |

### Phase D — 统一壳层 + Explore

| 步骤 | 文件 | 内容 |
|------|------|------|
| D1 | Explore 页面 | 数据总览 + AI 入口 + 地图入口 |
| D2 | 旧入口 wrapper | AIFeaturesPage 过渡跳转 |

---

## 七、待确认事项（需要你确认）

1. **v20 合并 poiName + chat 表** — 把两个 feature 放同一个 migration，减少版本碎片。是否同意？
2. **Phase C（Agent 框架）是否本次实施？** 计划说 P2 优先级，是否一起做还是先完成 Phase A+B 再说？
3. **Phase D（Explore 页面重构）是否本次实施？** 还是先让旧入口继续工作？
4. **地图选点页 400 行限制** — 如果需要拆分为 `map_picker/` 子目录，是否同意？
5. **Agent 网络搜索** — MVP 阶段 WebSearchTool 返回"暂不可用"，后续接入哪个搜索 API？

---

## 八、风险点

| 风险 | 缓解 |
|------|------|
| `_removeTagIdsColumnSafely` 在 `cleanupLegacyTagIdsColumn` 中可能被 onOpen 触发 | 必须在 CREATE TABLE 中加入 `poi_name` |
| `makeStreamRequestWithProvider` 改签名影响全局 | 不改签名，在 `streamAskQuestion` 内部自行构建 messages |
| flutter_map 增大包体积 | flutter_map 基于 OSM，体积可控（~200KB） |
| 回收站分支 v20 冲突 | 未来合并时回收站改为 v21 |
