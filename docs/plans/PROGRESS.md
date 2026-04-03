# 重构进度追踪

## Phase A — 基建层 ✅
- [x] A1: pubspec.yaml 新依赖
- [x] A2: chat_message.dart 扩展
- [x] A3: chat_session.dart 重写
- [x] A4: quote_model.dart poiName
- [x] A5: database_schema_manager v20
- [x] A6: chat_session_service.dart
- [x] A7: place_search_service.dart
- [x] A8: ai_request_helper createMessagesWithHistory
- [x] A9: ai_service streamAskQuestion history
- [x] A10: main.dart Provider 注入
- [x] A11: l10n keys
- **审查**: 0 error, 0 warning, 4 info ✅

## Phase B — 页面层 ✅
- [x] B1: note_qa_chat_page.dart 重写（持久化 + 多轮）
- [x] B2: map_location_picker_page.dart 新建
- [x] B3: 编辑器集成地图选点（长按）
- [x] B4: add_note_dialog poiName
- [x] B5: quote_item_widget poiName 显示优先级
- **审查**: 0 error, 0 warning ✅

## Phase C — Agent 框架 ✅
- [x] C1: agent_tool.dart 接口
- [x] C2: agent_tools/ 4个工具
- [x] C3: agent_service.dart 运行时
- [x] C4: agent_chat_page.dart
- [x] main.dart AgentService 注入
- **审查**: 0 error, 0 warning, 4 info ✅

## Phase D — 统一壳层 + Explore
**设计变更（2026-04-02 确认）：**
- Explore 页面保留原有统计类别（周期报告 + 洞察），只加一个 AI 入口 + 地图入口
- AI 入口进入后再分 Agent 模式和普通对话模式
- 原 AIFeaturesPage 改为 ExplorePage（保留原有 tab 结构 + 新增入口）

- [x] D1: explore_page.dart（原有统计 tab + AI 聊天入口 + 地图入口）
- [x] D2: home_page.dart 导航替换（第三 tab → ExplorePage）
- **审查**: 待执行

## 最终审查循环
- [ ] flutter analyze 全量
- [ ] 代码格式化 dart format
- [ ] 边界情况检查
- [ ] git add .
