---
name: project-docs-manager
description: "Manages ThoughtEcho's internal documentation and knowledge base in docs/. Categorizes docs, audits docs/INDEX.md, scaffolds new technical documents (audits, performance analyses, plans, handoffs, research) with standard naming conventions, and syncs key architecture decisions to docs/decisions.md. Trigger phrases: '整理文档', '归类文档', '更新文档索引', '新建交接', '新建性能分析', '新建架构审计', '新建技术方案', 'docs index', 'organize docs', 'scaffold doc'."
---

# Project Docs & Knowledge Base Manager

ThoughtEcho 项目内部研发知识库与历史记录管理技能。负责维护 `docs/INDEX.md` 全局索引矩阵、规范化创建技术文档，并在产生架构决议时与 `docs/decisions.md` 联动。

---

## 核心原则

1. **统一索引，单一真源**：所有研发文档必须在 [`docs/INDEX.md`](../../docs/INDEX.md) 中登记并标注生命周期状态（🔒 唯一事实源 / 🟢 活跃 / 📦 归档 / 🔍 调研）。
2. **规范命名**：一律采用 `docs/<topic>-<type>-YYYY-MM-DD.md`（或复杂子计划放入 `docs/plans/`），禁止出现模糊或无日期后缀的文件名。
3. **边界清晰**：
   - 通用技术审计、性能分析、主题设计、技术交接与方案归档放 [`docs/`](../../docs/)。
   - 架构决策总账记录于 [`docs/decisions.md`](../../docs/decisions.md)。
   - 团队角色画像、会话记录存放于 [`docs/squad/`](../../docs/squad/)。
   - 对外用户手册与代码规范同步由 `thoughtecho-docs-automation` 负责。

---

## 模式与操作流程

### 模式一：索引体检与自动整理（Catalog & Audit）

当用户提到「整理文档」、「更新文档索引」或发现有新文件未编目时触发：

1. **扫描目录**：扫描 `docs/`（含 `docs/plans/`）及 `.squad/` 下的所有 Markdown 文档。
2. **对比差异**：比对当前文件列表与 `docs/INDEX.md` 中的表格条目，找出缺失或路径不一致的文档。
3. **识别分类与状态**：
   - 属于哪一主题（核心规范 / 性能分析 / 主题系统 / Thoughter与AI / 同步网络与架构 / AI团队过程记录）。
   - 评估当前状态（是否为被取代的历史版本 `📦`，还是最新事实源 `🔒/🟢`）。
4. **更新索引**：就地更新 `docs/INDEX.md` 中的对应表格。

---

### 模式二：规范化脚手架创建（Scaffold New Document）

当需要开启新的技术探索、性能排查、架构设计或阶段交接时触发：

#### 1. 确定命名与路径
根据主题与类型自动生成文件名：
- 性能分析：`docs/<topic>-perf-analysis-YYYY-MM-DD.md`
- 架构/代码审计：`docs/<topic>-audit-YYYY-MM-DD.md`
- 方案规划：`docs/<topic>-plan-YYYY-MM-DD.md`
- 阶段技术交接：`docs/<topic>-handoff-YYYY-MM-DD.md`
- 深度技术调研：`docs/<topic>-research-YYYY-MM-DD.md`

#### 2. 标准文档模板
创建文档时使用以下结构：

```markdown
# [主题] [文档类型] (YYYY-MM-DD)

> **状态**：🟢 活跃 / 🔒 唯一事实源  
> **责任人 / 产出角色**：AUTO / EVE / Squad  
> **涉及模块**：lib/...  
> **关联历史**：[前置文档链接]

---

## 1. 背景与目标
[简述本次分析/设计所要解决的核心问题与技术痛点]

## 2. 现状剖析 / 测算数据
[列出核心数据、调用链路或现有实现瓶颈]

## 3. 技术方案 / 关键决议
[详细设计推导、选型对比与最终结论]

> [!IMPORTANT]
> 核心约束与红线（如禁止事項、不变量）

## 4. 影响范围与迁移清单
- [ ] 核心模型 / 数据库变更
- [ ] UI / 组件改造
- [ ] 自动化测试覆盖

## 5. 验证与后续交接
[如何验证方案有效性，后续接手需注意的事项]
```

#### 3. 自动登记与回填
文档创建后：
- 自动在 `docs/INDEX.md` 的对应主题表格中插入新行。
- 若在已有演进链中，更新上一篇文档的状态为 `📦 阶段交接` 或 `📦 历史参考`。

---

### 模式三：架构决策同步（Decisions Sync）

当新文档中产出了不可逾越的架构选型、数据模型隔离或重大设计决策时：

1. 提炼 1~2 段 ADR 决策摘要（包含背景、决议、否定方案与原因）。
2. 打开 [`docs/decisions.md`](../../docs/decisions.md)，在对应章节下追加标准决策记录：

```markdown
### YYYY-MM-DD: [决策标题]

- **背景**: [为什么需要做这个决定]
- **决议**: [最终采用的方案与核心约束]
- **否决方案**: [为什么不选方案 B/C]
- **详细文档**: [`docs/<filename>.md`](../docs/<filename>.md)
```

---

## 常见分类与主题词速查

| Topic 缩写 | 覆盖范围 |
|---|---|
| `note-list` | 笔记列表、Quill 前缀截取、冷启动、首屏渲染、帧预算 |
| `paper-ink-theme` / `theme` | 纸与墨/素笺主题、AppShapeTokens、Material 3、WCAG 对比度 |
| `thoughter` / `agent-memory` | Thoughter 助手、长期记忆库 agent_memory.db、画像包裹、工具调用 |
| `sync` / `localsend` / `webdav` | 数据同步、局域网传输、WebDAV 备份、断点续传、冲突合并 |
| `database` | 主库 schema、数据迁移、SQLite FFI 适配、查询性能 |
| `editor` | FlutterQuill 富文本编辑、卡片模板、媒体附件 |

---

## 反模式（严格禁止）

- ❌ 在仓库根目录或随机子目录下新建临时 `.md` 交接文档。
- ❌ 仅创建文档却不更新 `docs/INDEX.md`。
- ❌ 文档文件名不带日期或采用 `_v2`、`_final`、`_fixed` 等后缀。
- ❌ 把仅供内部研发阅读的性能审计或调试记录写入面向用户的 `README.md`。
- ❌ 篡改或推翻已在 `docs/paper-ink-theme-handoff-2026-07-31.md`、`docs/agent-memory-research-2026-08-08.md` 中定案的唯一事实源约束。
