# 📋 Agent 框架改进 - 快速参考

## 📊 关键数据对比

| 指标 | ThoughtEcho | Claude Code | 差距 |
|------|-----------|-----------|------|
| 工具数量 | 4 | 155+ | 需扩展 38x |
| 并发执行 | ❌ 顺序 | ✅ 智能批处理 | 性能瓶颈 |
| 权限管理 | ❌ 无 | ✅ 完整系统 | 安全风险 |
| 容量控制 | ❌ 无限制 | ✅ 50KB/200KB | 容易 OOM |
| 错误分类 | 基础 | 完善 | 难以调试 |
| 执行追踪 | 基础事件 | 完整日志 | 缺分析数据 |

---

## 🔴 P0 优先做（本周）

### 1️⃣ 容量管理系统
**问题**: 工具结果无限制，大数据易导致 OOM  
**方案**: 3 层限制 → 单工具 50KB + 单消息 200KB + 智能文件存储

```dart
// 新增: lib/services/agent_result_manager.dart
class ToolResultCapacity {
  static const maxResultChars = 50_000;      // 单工具
  static const maxPerMessageChars = 200_000; // 单消息
}
```

**预期收益**: 防止 OOM、支持大文件、提升稳定性

---

### 2️⃣ 基础权限框架
**问题**: 所有工具无条件信任，安全隐患  
**方案**: 3 级权限 → Always/OncePerRun/Never

```dart
// 新增: lib/services/agent_permissions.dart
enum ToolPermissionLevel { always, oncePerRun, never }

// 权限配置
const defaultPermissions = {
  'web_fetch': ToolPermissionLevel.always,      // 信息获取
  'edit_notes': ToolPermissionLevel.oncePerRun, // 修改数据
};
```

**预期收益**: 用户控制工具、防止误操作

---

## 🟡 P1 优先做（1-2周）

### 3️⃣ 并发执行系统
**问题**: 工具顺序执行，无法利用 I/O 并发  
**方案**: 智能批处理 → 读操作并发 + 写操作顺序

```dart
// 改进: agent_service.dart
// 分区: 可并发的读操作单独批处理
for (final batch in partitionToolCalls(toolCalls)) {
  if (batch.isConcurrencySafe) {
    // 并发执行: web_search, web_fetch 等
    await Future.wait(batch.calls.map(executeToolSafely));
  } else {
    // 顺序执行: edit_notes 等写操作
    for (final call in batch.calls) {
      await executeToolSafely(call);
    }
  }
}
```

**预期收益**: 执行速度提升 30-50%

---

### 4️⃣ 工具库扩展（第一批）
**建议添加工具**:
- `NotesEditTool` - 编辑笔记（权限: OncePerRun）
- `QuoteQueryTool` - 高级查询（权限: Always）
- 增强 `WebSearchTool` - 搜索缓存 + 排序
- 增强 `ExploreNotesTool` - 相关度排序

**收益**: Agent 功能完整度提升

---

## 🟢 P2 优先做（3周+）

### 5️⃣ 错误分类与重试
**问题**: 错误处理粗糙，难以调试  
**方案**: 错误分类 → 6 种类型 + 自动重试

```dart
enum ToolErrorType {
  networkError,      // 可重试
  validationError,   // 不可重试
  permissionError,   // 需授权
  timeoutError,      // 可重试
  resourceExhausted, // 需清理
  malformedResponse, // 需修复
}
```

---

### 6️⃣ 执行日志与分析
**建议实现**:
- 工具调用时间线
- 权限决策审计日志
- 性能指标（Duration/Tokens）
- 错误率统计

**UI 展示**: Agent 执行摘要面板

---

## 📈 实现时间表

```
第1周:
  ✓ 容量管理系统 (1-2 天)
  ✓ 权限框架基础 (2-3 天)

第2周:
  ✓ 工具库扩展 (3-5 天)
  ✓ 并发执行系统 (2-3 天)

第3周+:
  ✓ 错误分类与重试 (1 天)
  ✓ 执行日志系统 (1-2 天)
  ✓ 权限规则引擎 (5-7 天)
```

---

## 🎯 关键代码位置

### 需要修改
- `lib/services/agent_service.dart` - Agent 循环（添加容量检查 + 权限检查）
- `lib/services/agent_tool.dart` - Tool 基类（添加并发标志 + 超时配置）
- `main.dart` - Provider 注入（添加新的服务）

### 需要新增
- `lib/services/agent_result_manager.dart` - 容量管理
- `lib/services/agent_permissions.dart` - 权限系统
- `lib/services/agent_tool_executor.dart` - 并发执行
- `lib/services/agent_error_handler.dart` - 错误处理
- `lib/services/agent_execution_logger.dart` - 执行日志

---

## ✅ 完成检查清单

### 容量管理
- [ ] 创建容量管理服务
- [ ] 修改 agent_service 集成
- [ ] 测试大文件场景
- [ ] UI 展示截断提示

### 权限系统
- [ ] 定义权限级别
- [ ] 创建权限管理器
- [ ] 实现权限对话框
- [ ] 权限决策日志

### 并发执行
- [ ] 实现工具分区算法
- [ ] 实现并发执行
- [ ] 集成 agent_service
- [ ] 并发安全性测试

### 工具扩展
- [ ] NotesEditTool
- [ ] QuoteQueryTool
- [ ] WebSearchTool 增强
- [ ] ExploreNotesTool 增强

---

## 📚 参考资源

**完整分析文档**: `AGENT_FRAMEWORK_ANALYSIS.md`

**Claude Code 参考**:
- Tool 系统: `src/tools/` (~155 个)
- 容量限制: `src/constants/toolLimits.ts`
- 权限系统: `src/hooks/toolPermission/`
- 错误处理: `src/utils/toolErrors.ts`

---

**上次更新**: 2026-04-18  
**状态**: 待实现
