# ThoughtEcho v4.1.0 · 足迹漫步与 Thoughter 深度漫游 / Release Notes

> [!NOTE]
> ### 🚀 ThoughtEcho v4.1.0 版本发布
> 本次更新带来地图足迹回忆与附近地点选择、Thoughter 梦境整理与交互式向导、新增卡片快捷复制笔记内容，以及多项数据安全与运行性能改进。
> 
> 📖 **用户指南**: https://note.shangjinyun.cn/user-guide.html  
> 💡 **Thoughter 专属介绍**: https://note.shangjinyun.cn/thoughter/  
> 🌐 **官方网站**: https://note.shangjinyun.cn/

> ⚠️ **重要通知**：本版本引入了匿名用户体验改进计划（**默认彻底关闭**），仅在手动开启后记录基础功能开关状态，绝不收集笔记与隐私内容，可在「设置 › 反馈与联系」中随时管理。

> [English Version](#english-version)

---

## 🙋 用户篇：新特性与体验优化

### 🗺️ 足迹与地图回忆
- **附近地点选择**：
  - 新增地点选择器，记录笔记时可直接搜索附近的具体建筑或商圈。
  - 自动整理为清晰的「市 · 区」地名，取代原本冗长生硬的地理坐标。
  - 支持直接在列表里快速检索与挑选，也可以在地图上浏览定位。
- **探索页里的地图回忆**：
  - 在「探索」页新增「地图回忆」入口，将你曾在不同旅途与角落写下的心迹呈现在地图上。
  - 点击地图上的足迹点，即可展开在该地写过的笔记，重温当时的心境。
- **位置与天气轻松修改**：
  - 重构了编辑笔记时的元数据修改窗口，随时可以更换地点或天气，不需要时也能一键清除。

### 💡 Thoughter 梦境整理与互动
- **梦境整理 (Dreaming)**：
  - 当你在应用中停笔休息、应用处于空闲时，Thoughter 会在后台默默整理你的文风习惯与偏好，让后续的交流更懂你。
  - 整理过程在后台静默进行，不会打扰你当前的阅读与记录。
- **交互式选项向导**：
  - 协助推敲思路或确认文段时，Thoughter 能以卡片形式提供清晰的选项或问答向导，方便你直接点选确认，不用频繁打字。
- **长期记忆直观管理**：
  - 在「设置 › 长期记忆」中可以清楚看到 Thoughter 记下的偏好事实与对应笔记出处。所有记忆都支持单条修改或随时彻底清空。
- **对话历史批量清理**：
  - AI 对话历史支持左滑快速删除单条记录，也支持长按多选后批量清理，随时保持列表清爽。

### 📝 记录细节打磨
- **新增笔记快捷复制**：
  - 笔记卡片菜单新增「复制文本」选项，支持一键复制整篇笔记内容。
  - 复制纯文本的同时，若笔记包含作者或出处，会自动排在下一行，排版干净，方便摘录与向外分享。
- **标签设置页视觉统一**：
  - 标签管理页接入当前主题风格，圆角与色彩和整套应用更加协调。

### 🛡️ 隐私与数据透明
- **引入匿名使用统计 Aptabase（默认关闭）**：
  - 为了解基础功能的使用情况以指导后续改进，本版本引入了开源且注重隐私的 Aptabase 统计组件。
  - **默认关闭**：遵循本地优先与隐私主权，**该功能默认为关闭状态**。
  - 仅在用户主动在设置中开启后，才会记录极少量无个人身份信息的开关状态（如某项设置是否启用）。
  - **绝不**收集任何笔记内容、图片、位置或个人隐私数据。代码完全开源透明。
- **应用内数据收集披露**：
  - 在「设置 › 反馈与联系」中增加了透明的数据收集说明与源码查阅链接，随时可以关闭或撤回。

---

## 💻 开发者篇：架构重构、安全与性能

> 📑 **研发知识库与全量技术文档索引**：[`docs/INDEX.md`](INDEX.md)

### 🔒 安全防护与凭证治理
- **WebDAV 同步防路径穿越**：
  - 严格规范化远端请求路径，过滤多重 URL 编码（如 `%252e%252e`）及跨目录遍历尝试；安全编码媒体附件文件名，防止异常覆盖。
  - 内存凭证脱敏：在内存中规范处理 Basic Auth 认证信息，捕获网络异常时彻底剥除密码与敏感参数，避免明文凭证进入日志。
- **旧版 API 密钥物理清理**：
  - 启动阶段自动检索旧版本在 SharedPreferences 与 MMKV 中散落的 API 密钥片段，迁移至安全存储（`APIKeyManager`）后原地彻底擦除。
- **SQL 注入防范与数据安全**：
  - 全面下沉动态 SQL 查询，严格杜绝未参数化查询；针对 SQLite 聚合 `COUNT` 结果强化类型解析（`int` / `num` / `String` 容错），消除潜在崩溃风险。

### ⚡ 性能优化与内存减负
- **高频字符串解析减少内存分配**：
  - 优化标签分割与坐标解析中的高频逗号分隔逻辑，静态预编译正则表达式并减少短生命周期字符串分配，降低垃圾回收频率。
- **临时媒体文件异步清理**：
  - 临时图片清理与扫描改为异步流式处理，避免大量文件操作造成界面卡顿。
  - `MediaReferenceService` 引入批量查询与预加载 Map，消除媒体引用检查中的 N+1 查询瓶颈。
- **同步冲突与数据导入加速**：
  - 优化 WebDAV 冲突克隆时的标签批量写入机制与 `AddNoteController` 标签预载入，提升数据库批量操作效率。

### 🧪 自动化测试
- 补充了 `NearbyLocationPicker`、`AskUserCard`、`DreamingService`、`AgentMemoryService` 等模块的单元与组件测试，核心功能全量门禁保障稳定。

---

<a id="english-version"></a>

## 🌐 English Version

### 🚀 ThoughtEcho v4.1.0 Release Notes · Footprint Wander & Thoughter Deep Roaming

ThoughtEcho v4.1.0 brings map memories and nearby place selection, Thoughter Dreaming and interactive guidance wizards, note content copying with clean attribution formatting, along with security hardening and transparent privacy practices.

> ⚠️ **Important Notice**: This release introduces an anonymous user experience improvement program (**completely disabled by default**). Only when manually enabled does it record basic feature toggle statuses, never collecting note content or private data. It can be managed anytime under Settings › Feedback & Contact.

---

### 🙋 For Users: Features & Improvements

#### 🗺️ Footprints & Map Memories
- **Nearby Place Picker**:
  - Quickly search and pick nearby places when writing notes.
  - Automatically formats clear "City · District" names, replacing confusing raw coordinate strings.
  - Supports quick list searching and map browsing to pick locations.
- **Map Memories in Explore**:
  - Open "Map Memories" in Explore to view notes you wrote across different places on an interactive map.
  - Tap any place marker to read past notes written at that spot.
- **Easy Location & Weather Editing**:
  - Edit or clear location and weather metadata directly while revising notes.

#### 💡 Thoughter Dreaming & Guidance
- **Dreaming (Background Reflection)**:
  - When the app is idle, Thoughter gently reflects on your writing habits in the background to better tailor future conversations.
  - Runs quietly in the background without interrupting your current writing.
- **Interactive Step Wizard**:
  - When brainstorming or revising text, Thoughter can present structured choices and questions as cards, letting you tap to confirm without typing.
- **Direct Memory Management**:
  - View stored preferences and their source notes under Settings › Long-Term Memory. Edit or clear any memory at any time.
- **Session History Cleanup**:
  - Swipe left to quickly delete a conversation, or use multi-select to clear multiple chats at once.

#### 📝 Everyday Writing Touches
- **Copy Note Content**:
  - Added "Copy Text" to the note card menu to copy the entire note content with a single tap.
  - If the note includes an author or source, it is automatically formatted on the subsequent line for tidy sharing.
- **Cleaner Tag Settings**:
  - Aligned tag settings with current theme styles for consistent colors and corner shapes.

#### 🛡️ Privacy & Transparency
- **Anonymous Telemetry via Aptabase (Disabled by Default)**:
  - We integrated the open-source, privacy-focused Aptabase component to track general feature usage for ongoing improvements.
  - **Off by Default**: In keeping with our local-first philosophy, **this feature is disabled by default**.
  - Only when manually turned on will it log basic, non-personally identifiable toggle events (such as whether a setting is enabled).
  - We **never** collect note text, images, location data, or personal details.
- **In-App Data Collection Disclosure**:
  - Clear explanations and source code links are available under Settings › Feedback & Contact.

---

### 💻 For Developers: Architecture, Security & Performance

#### 🔒 Security & Credential Protection
- **WebDAV Path Traversal Defense**:
  - Standardizes remote paths, blocks multi-encoded traversal attempts (`%252e%252e`), and safely encodes attachment names.
  - In-memory Basic Auth credentials are stripped from network error logs to avoid plain-text exposure.
- **Legacy API Key Cleanup**:
  - Automatically migrates and scrubs any legacy API key fragments from SharedPreferences and MMKV into secure storage (`APIKeyManager`).
- **SQL Hardening & Safe Type Parsing**:
  - Enforces parameterized queries and hardens SQLite aggregate `COUNT` return type parsing.

#### ⚡ Performance & Memory Efficiency
- **Reduced GC Pressure**:
  - Precompiled regexes and lazy iterables reduce temporary string allocations during comma-separated parsing.
- **Async Temporary Media Cleanup**:
  - File cache expiration and cleanup run asynchronously to avoid UI frame drops.
  - Batch queries in `MediaReferenceService` eliminate N+1 lookup bottlenecks.
- **Faster Sync & Import**:
  - Tag batch insertion during conflict resolution and tag caching improve bulk database throughput.

#### 🧪 Testing
- Added unit and widget tests for `NearbyLocationPicker`, `AskUserCard`, `DreamingService`, and `AgentMemoryService`.
