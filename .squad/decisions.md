# 决策记录

> 团队所有重要决策的权威记录

---

## 2026-04-06: 团队成立

**决策者**: 上晋 + Squad
**内容**: 
- 成立 9 人 AI 团队（+ Scribe + Ralph）
- 团队使用《机器人总动员》宇宙命名
- 所有成员使用中文沟通
- 成员必须主动联网搜索最新信息

**原因**: 上晋是创意者（Vibe Coder），不负责技术细节，团队全权执行

---

## 2026-04-06: 记录规范

**决策者**: 上晋
**内容**: 团队在所有文件记录中保持开源友好的内容标准

---

## 2026-04-06: 产品现状分析（WALL·E）

**决策者**: WALL·E (产品顾问)  
**类型**: 产品分析

**核心发现**:
- 项目规模：成熟的中大型 Flutter 应用（68+ 服务、35+ 页面、45+ 组件）
- 已上架：Microsoft Store (9NC7GDG6KFMC)，应用名称 "ThoughtEcho - Free download and install on Windows"
- 核心功能完整度：⭐⭐⭐⭐⭐

**产品独特卖点**:
1. **AI 深度集成** — 贯穿全生命周期（问答、润色、洞察、年度报告）
2. **本地优先策略** — 数据不上云，隐私有保障
3. **情境感知** — 自动记录位置、天气、时间段
4. **跨平台一致** — Windows/Android/iOS Material 3 现代界面

**竞品定位**: 介于 Obsidian（极客向）和 Day One（日记向）之间，定位 "重视隐私的 AI 笔记应用"

**短期优化建议**:
- [ ] AI 自然语言搜索
- [ ] 智能标签推荐
- [ ] 快速入口优化（减少启动到记录步骤数）

**中期功能建议**:
- [ ] 语音输入（PR #117 开放中）
- [ ] OCR 拍照识别（PR #128 已关闭）
- [ ] Widget 桌面小组件

**结论**: 功能成熟度已具备上线运营条件，下一步聚焦**降低使用门槛**和**增强发现感**

---

## 2026-04-06: 用户反馈与技术债分析（VN-GO）

**决策者**: VN-GO (用户研究员)  
**类型**: 用户研究 + 技术债评估

**紧急发现**:
1. **用户反馈渠道缺失** — GitHub Issues = 0，无 App Store / Google Play 评价入口
2. **安全性技术债** — SQL 注入、XSS、Zip Slip 路径穿越、不安全本地存储
3. **国际化不一致** — UI 仍有中文硬编码（多次 "提取硬编码" PR 表明）

**开发进度分析**:
- 193 个 PR 以内部开发为主（AI 团队、安全修复、性能优化）
- 25 stars / 4 forks，早期成长阶段

**待完成功能**:
| 功能 | 状态 | 备注 |
|------|------|------|
| 语音转文字 | 🚧 PR #117 | Whisper + sherpa-onnx 方案 |
| OCR 识别 | ❌ 已关闭 | PR #128 |
| 地图选点 | 🚧 PR #181 | Phase A-D |
| 回收站软删除 | 🚧 PR #163 | |

**优先建议**:
1. 完成 PR #117 语音识别 — 差异化卖点、移动端刚需
2. 建立用户反馈渠道 — Issues 模板、应用内反馈入口
3. 安全审计 checklist — 每次 release 前强制检查
4. 国际化检查流程 — 防止新增硬编码

**结论**: 团队应在扩大用户接入前完成安全审计；优先完成语音识别以强化差异化

---

## 2026-04-06: 商店上架现状（PR-T）

**决策者**: PR-T (商店运营)  
**类型**: 商店运营 + 发布规划

**发布现状**:
| 商店 | 状态 | 信息 |
|-----|------|------|
| Microsoft Store | ✅ 已上架 | https://apps.microsoft.com/detail/9NC7GDG6KFMC，发布者 Shangjinyun |
| Google Play | ❓ 未确认 | 待规划 |
| App Store | ❓ 未确认 | 待规划 |

**版本同步**:
- 代码版本: 3.4.0+1
- MSIX 版本: 3.4.0.0（符合 MS Store 规范）
- Identity Name: Shangjinyun.330094822087A

**商店资产完整度**:
- ✅ Windows Tiles 图标（44x44, 71x71, 150x150, 310x310, Wide310x150）
- ✅ 应用图标 (ICO + PNG)
- ✅ README 截图 (13 张核心功能)
- ✅ 英文商店描述（详尽、功能分类清晰）
- ✅ CI/CD 发布流程（`build-windows.yml`, `flutter-release-build.yml`, `ios-build.yml`）

**改进建议**:
1. 添加 Google Play / App Store 链接到 README
2. 提交中文商店描述本地化
3. 定期更新商店截图为最新 UI 版本
4. ASO 优化：强化"AI 驱动"卖点，关键词优化

**下一步行动**:
- [ ] 确认 Google Play 上架计划
- [ ] 确认 App Store 上架计划
- [ ] 准备中文商店描述
- [ ] 规划截图更新流程

**结论**: 商店运营已成熟，应拓展到主流应用商店并完善本地化

---

## 2026-05-17: 长列表滚动性能优化架构决策

**决策者**: 上晋 + 性能顾问 (AI)
**类型**: 技术架构决策 / 性能优化

**背景**:
长列表在包含复杂富文本、图片等未知高度元素时，快速滑动会出现严重的卡顿（"一顿一顿"和掉帧），主要由于构建开销 (Build) 剧烈增加和频繁的重绘引起。

**核心决策**:
1. **停止过度设计，回归原生渲染**: 彻底废弃 "依赖 `isListScrolling` 监听状态频繁开启/关闭模糊滤镜" 的做法，转而信任并长驻 Flutter 原生的 `BackdropGroup` + `BackdropFilter.grouped` 进行高效模糊处理。
2. **废除图片延迟加载探照灯**: 移除 `_LazyQuillImage` 中的 `VisibilityDetector`。在高度未知的富文本场景中，依靠滚动进视口后再加载会触发极其严重的 Layout Shift (视口跳变)，瞬间带来严重的构建卡顿（worstBuild 高达 30ms+）。
3. **拥抱大缓存区预加载**: 将 `ListView` 的 `cacheExtent` 从极短的 `250` 大幅拉长至屏幕高度的 1~2 倍（`clamp(400, 900)`）。

**原因**:
- 富文本中的图片因缺乏明确宽高，最佳实践"固定宽高占位符"在当前场景不可行。
- 权衡之下，通过加大 `cacheExtent` 使得手机在视口外"强行"预先加载和排版图片，是在没有上帝视角情况下的**最合理启发式解法**。
- `BackdropGroup` 已经被证明开销极低，频繁通过监听滑动状态反向卸载/加载特效是典型的好心办坏事，引发了全列表频繁集体 Rebuild。
- 此次改动后，经过真机实测，千帧以上的复杂图文长滑动，平均帧耗时成功从卡死级别压到了 `5.8ms`，仅出现 1 次极轻微掉帧。

**结论**: 在 Flutter 中处理高度未知的复杂列表卡片时，应坚决防止 Layout Shift 和无意义的频繁重构，善用大缓存预构建与高效原生组件特性。

---

## 2026-05-31: 列表语义性能优化决策

**决策者**: 性能顾问 (AI)
**类型**: 性能优化

**背景**:
根据 2026-05-17 的架构决策，团队将 `ListView` 的 `cacheExtent` 提高到了 `400~900` 以预加载解决布局跳变（Layout Shift）导致的重绘卡顿。但在最新的 Profile 性能测试中发现，由于预加载了大量屏幕外的笔记卡片，Flutter 引擎需要为这些卡片构建庞大的无障碍语义树（Semantics Tree），导致 `PipelineOwner.flushSemantics` 耗时飙升，占用 UI 线程约 31% 的时间，产生了严重的掉帧卡顿（UI 线程最高 98ms，Raster 最高 127ms）。

**核心决策**:
1. **彻底分离视觉与语义**: 对于 `QuoteItemWidget` 中所有不需要被屏幕朗读的纯视觉组件（如 `BackdropFilter` 毛玻璃、`LinearGradient` 渐变遮罩、装饰性 `Icon` 等），强制使用 `ExcludeSemantics` 进行包裹。
2. **列表级别语义控制**: 在 `NoteListView` 的 `ListView.builder` 层级，评估并考虑增加 `addSemanticIndexes: false`，避免为大量缓存卡片强制建立细粒度的列表语义索引，从而减少 `flushSemantics` 负担。

**原因**:
- `ExcludeSemantics` 对视觉渲染完全无损（0 像素变化），仅在数据层面上截断无障碍树的生成。
- 大缓存区（`cacheExtent`）是必须保留的（为了防抖动），在此前提下，精简语义树是降低主线程 Build 阶段后置开销的唯一也是业界最佳实践。

**结论**: 立即在 `quote_item_widget.dart` 内部铺设 `ExcludeSemantics` 进行语义裁剪，切断长列表预加载带来的无谓性能开销。

---

## 2026-06-09: NoteListView 滚动卡顿定位进展

**决策者**: Codex + 上晋
**类型**: 性能定位 / 实测结论

**已确认现象**:
- Firebase 与真机日志都显示，数据库查询和 `itemBuilder` 本身不是主要瓶颈；真实列表中
  `itemBuilder` 量级约为 0.1ms 以内。
- 新增的 item layout 探针显示，首次进入视口的富文本/图文卡片会产生真实主线程布局尖峰：
  `rich-image` 常见 10-22ms，单个 `rich` 样本曾达到 67ms。
- 仍存在一类未完全解释的 build 尖峰：例如 `worstBuild=114ms` 时，
  `itemLayout.worst=2.6ms` 且内容缓存无 miss。这说明卡顿不是单一来源，
  还需要继续关注祖先重建、GC、Flutter 帧管线或其他同步任务。

**当前优化方向**:
1. 优先削减 `QuoteItemWidget` 在普通折叠滚动状态下的隐式动画和重型布局开销。
2. 保持视觉像素不变；选择态、展开态等用户可见状态变化仍保留动画。
3. 不重新引入“滚动中关闭模糊”的方案。历史结论显示该方案会因为滚动状态切换导致全列表重建，属于负优化，除非未来有不触发列表重建的新实现。

**后续判断标准**:
- 如果下一版日志中 `slowLayouts` 明显下降，但仍有高 `worstBuild`，应继续补帧级任务探针或结合 Perfetto/Sentry 定位非 item layout 来源。
- 如果 `slowLayouts` 未下降，则优先拆解 `QuoteContent`/FlutterQuill 布局和媒体占位高度稳定性。

**结论**: 当前可以确定“富文本/图文卡片首次布局”是主要可优化项之一，但不是全部卡顿来源；后续优化必须同时保留对非 item layout build 尖峰的定位能力。

---

## 2026-06-09: Codex 自动化测试性能结论与正式版实验开关

**决策者**: Codex
**类型**: 性能诊断与开关方案

**Codex 测试与诊断结论（原话记录）**：

> 当前最重要结论：有效 Firebase A/B 显示，关闭卡片视觉重效果后，真实列表指标大幅改善：
>
> - richText：`build99 71.9ms → 36.1ms`，`raster99 190.8ms → 1.8ms`
> - images：`build99 58.7ms → 23.0ms`，`raster99 206.9ms → 10.1ms`
>
> 但这个 A/B 同时关了阴影和 BackdropFilter，所以还不能说“就是阴影”或“就是模糊”。我已经把拆分诊断推上去了：只关阴影、只关 BackdropFilter、全关。刚才继续跑 Firebase 时失败，原因是 Firebase Test Lab `TEST_QUOTA_EXCEEDED`，不是代码问题。
>
> 已推到 `main`：`f14d2517 feat(settings): add note list visual effect toggles`
>
> 这次加的是发布版也可用的开发者模式实验开关，默认都关闭，不改变现有视觉效果：
>
> - `[实验] 记录页禁用卡片阴影`
> - `[实验] 记录页禁用折叠模糊`
>
> 位置在设置页的开发者模式区域。用于你在正式 APK 里直接切换实际观感和体感，不需要我再改代码才能比较。
>
> 验证已跑：
>
> - `flutter analyze --no-fatal-infos ...` 通过
> - `flutter test test/unit/models/app_settings_test.dart` 通过
> - `flutter test test/unit/services/settings_service_test.dart` 通过
> - `flutter test test/widgets/quote_item_widget_test.dart` 通过
>
> 没有在这台机器构建 APK。Firebase 暂时没再跑，因为前面已经遇到 `TEST_QUOTA_EXCEEDED`，现在触发大概率还是浪费额度。

---

## 2026-06-13: 记录页卡顿根因复核（待实测验证）

**决策者**: 上晋 + 性能顾问 (AI / Claude)
**类型**: 性能定位复核 / 待验证假设

**复核动机**:
用户反馈：即使在正式版（main, `f14d2517`）打开“禁用卡片阴影”和“禁用折叠模糊”两个实验开关，
记录页仍然首次滑动卡、之后上下滑有小卡顿，只是略微改善。需要复核“是不是阴影/模糊”这一结论。

**已核实的事实（非猜测）**:
1. 实验开关 commit `f14d2517` 只在 main，不在 `fix/add-note-dialog-keyboard-jank` 分支；
   `fix/add-note-dialog-keyboard-jank` 相对 main 无独有 commit（diff 为空），其内容已全部在 main 中，
   不需要单独并入 main。
2. 阴影/模糊主要影响 GPU 光栅线程（`raster99`），Codex A/B 实测 `raster99 190.8ms → 1.8ms`；
   而用户体感的“首次滑动卡 / 上下滑小卡顿”属于 UI 线程 build/layout 尖峰（`build99 ~71ms`）。
   两者是不同线程的不同问题，因此“关掉阴影/模糊仍卡”与现有数据一致，并不矛盾。
3. Codex 自己记录的反证：`worstBuild=114ms` 时 `itemLayout.worst=2.6ms` 且缓存无 miss，
   说明阴影/模糊不是 UI 线程尖峰主因。

**主因假设（高度怀疑，待 log/Timeline 确证，尚未定论）**:
- `lib/widgets/quote_content_widget.dart` 中，每条富文本笔记（`editSource == 'fullscreen'`）
  在列表 cell 内都用一个完整的 `flutter_quill` (11.5.0) `QuillEditor` 实例渲染。
- `QuillEditor` 即便只读（`showCursor:false` / `enableInteractiveSelection:false`），
  仍是为编辑设计的重型组件（内部含 RenderEditor、逐行 RenderObject、文本输入/选区层）。
  将其用于长列表只读展示，首次进入 `cacheExtent`(400~900px) 时集中触发 `performLayout`，
  推断是 `rich`/`rich-image` 首次布局尖峰（10~67ms）与 `flushLayout 26%` / `TextPainter.layout 10%` 的来源。
- 现有 `_QuoteContentControllerCache` / `_QuoteDocumentCache` 只缓存了 Document 解析与控制器创建，
  **无法消除 QuillEditor 自身首次布局成本**，因此控制器无 miss 时仍出现高 build。

**待验证项（必须拿到下列任一才能定论，不得据旧数据拍板）**:
1. 最新 scroll session 应用内日志：`slowLayouts` 中 `rich`/`rich-image` 的 ms 分布与数量、
   `worstBuild` 对应 `itemLayout.worst`、缓存行 `ctrlMiss+`/`ctrlWorkUs+`。
2. DevTools/Perfetto Timeline 导出，确认 UI 线程 `performLayout` 火焰图中 QuillEditor 占比。

**候选方向（验证后再实施，本次不动视觉）**:
- 折叠态/非展开态富文本改用轻量只读渲染（Delta → `TextSpan` + `RichText`，图片用占位/缩略），
  仅在用户展开该条时才实例化真正的 `QuillEditor`；预期把首次布局从 10~67ms 压到 ~1-2ms，
  且折叠态可见效果不变。
- 注意：已有分支 `perf/note-list-stutter`（`5f2710ad` 将 quill delta json 解析移入后台 isolate）
  方向相关，后续可参考但需独立验证其是否触及布局成本本身（JSON 解析≠布局）。

**本次已批准的低风险改动（用户同意，不改变视觉）**:
- 折叠态静态卡片的阴影：当前静态卡走普通 `Container` 无 `RepaintBoundary` 隔离，
  阴影 `BoxShadow` 高斯模糊每帧重算。计划用 `RepaintBoundary` 隔离卡片绘制以缓存阴影栅格，
  滚动时仅做位移合成。视觉像素不变。

**结论**: “阴影/模糊是主因”不成立；最可能的 UI 线程主因是列表内 `QuillEditor` 的首次布局，
但在拿到用户最新实测日志前，此为待验证假设，不作为已定论结论。

---

## 2026-06-13: 实测确证 + 修复计划

**决策者**: 上晋 + 性能顾问 (AI / Claude)
**类型**: 性能根因确证 / 修复计划

**实测确证（用户提供 main `f14d2517` 真机日志，已不再是假设）**:
对照同一段“向下滑第二屏”：

| 指标 | 视觉效果全关 | 视觉效果全开 |
|---|---|---|
| worstBuild | 88.8ms | 145.4ms |
| worstRaster | 10.2ms | 95.7ms |
| itemLayout.worst | 39.1ms (rich) | 51.5ms (rich) |

- 阴影/模糊只影响 raster 线程（worstRaster 95→10ms），关掉确实有用但治标。
- 即便全关，worstBuild 仍 88ms、单条 rich 卡片首次 layout 仍 39ms，远超 16.7ms 帧预算，
  与用户“关了还是卡”体感一致。
- `slowLayouts` 每个尖峰均为 `rich`/`rich-image` 且 `h=none→324`（首次布局）。
  向上滑回时同卡片变 `h=324→324`，layout 掉到 0.1~0.5ms、frameJank=0。
- 结论：**主因 = 列表内 `QuillEditor` 渲染折叠态富文本的首次 `performLayout`**。
  “等一会儿再滑”无效，因为 layout 只在 cell 进入视口时发生，缓存/预热/keepAlive 只省 build 与
  Document 解析，省不掉 QuillEditor 首次布局。

**已废弃方案**:
- “全部 item 无条件 keepAlive”（stash 实验）已丢弃：保活只防重复 layout，不解决首次 layout，
  且长列表内存/element 无上限增长。
- “低性能模式开关”暂不做，仅作第二步视觉还原失败时的 Plan B。

**修复计划**:
1. **（已实施）阴影 RepaintBoundary**：折叠态静态卡片用 `RepaintBoundary` 隔离，缓存阴影栅格，
   滚动仅位移合成。视觉零变化。见 `lib/widgets/quote_item_widget.dart` 末尾 return 分支。
2. **（待办，核心）折叠态富文本弃用 `QuillEditor`**：折叠态改 Delta→`TextSpan`/`RichText` 轻量只读
   渲染，图片复用现有 embed 组件；仅展开单条时实例化真正 `QuillEditor`。预期首次 layout 10~50ms→1~2ms。
   主要风险为视觉还原度，须先写渲染器 + 真实笔记截图对照测试，达标方可合入。
3. **（待办，可选）高度占位**：用 `_estimateDeltaHeight` 估算值给未布局 cell 占位，减少 `h=none`
   滚动范围漂移。第二步完成后视数据决定是否需要。

---

## 2026-06-30: 记录页固定位置短暂停住复核

**决策者**: Codex + 上晋
**类型**: 性能定位 / 快速修复

**现象**:
用户反馈当前向下滑整体已经较流畅，但会在某个位置“完全卡住”，短暂等待后才能继续下滑。

**判断**:
- 这类“固定位置停住后继续”的体感更像分页边界等待，而不是阴影/模糊或 QuillEditor 首次布局。
- 当前记录页每页 20 条，旧预加载阈值为当前已加载滚动范围的 65%。快速下滑时可能先撞到当前页末尾，
  等下一页查询和列表更新回来后才能继续滚动。
- QuillEditor 首次布局仍是富文本卡片的长期优化项，但本次小修不触碰富文本渲染和视觉效果。

**快速修复**:
- 将 `AppConstants.scrollPreloadThreshold` 从 `0.65` 调整为 `0.35`。
- 新增 Widget 回归测试：当滚动到当前页 50% 时，应已经触发下一页加载，避免用户接近页尾才开始查询。

**风险**:
- 会更早发起分页查询，轻微增加提前加载概率；但仍有 `_isLoading` 串行保护，不会并发多页加载。
- 如果后续日志显示停顿仍伴随 `rich/rich-image` 首次 layout 尖峰，再回到轻量富文本预览器方案。

---

## 2026-07-02: 记录页卡顿综合复核 + 分步优化计划

**决策者**: 上晋 + Claude Fable 5（判断者）+ Codex（执行者）
**类型**: 根因复核 / 外部分析核实 / 分步实施计划

### 一、对历史决策的复核结论

- 2026-05-17 / 05-31 / 06-13 / 06-30 各决策方向正确、有实测数据支撑，无需推翻。
- 2026-06-13 标注"（待办，核心）"的修复——折叠态弃用 QuillEditor——**至今未实施**。
  已核实 `quote_content_widget.dart` 的 `build()` 中折叠态富文本仍实例化完整 `quill.QuillEditor`。
  此前多轮模型的优化（Document/Controller 缓存、预热、语义裁剪、RepaintBoundary、分页阈值）
  均为外围优化，无法消除 QuillEditor 首次 `performLayout`（实测 10~67ms/条），
  这是"怎么优化都没用"的根本原因。
- 关键机理（解释"首滑卡、之后顺"）：卡片首次进入视口/cacheExtent 时 `h=none→324` 布局
  10~67ms；回滑时 `h=324→324` 仅 0.1~0.5ms。布局结果活在 render 树中，
  每张卡的首次布局一个会话只发生一次，故卡顿集中在首滑。

### 二、对 Gemini 3 DeepThink 外部分析的逐条核实（重要：防止未来重复排查）

| # | Gemini 指控 | 核实结论 |
|---|---|---|
| 1 | loadMore 递增 `_resultsVersion` 导致 AnimatedSwitcher 整棵换树 | **不成立（已过时）**。`note_list_data_stream.dart` 明确注释并实现：load more **不**递增 `_resultsVersion`，仅搜索 query 变化的首次事件递增。勿重复"修复" |
| 2 | 每次 setState 重建 tagMap / rowIndexByKey | **属实但量级小**。O(n) map 构建在每次 `_buildNoteList` 执行，n≈已加载条数，微秒级。低优先级 |
| 3 | 顶层宽依赖：`Provider.of<NoteSearchController>(listen:true)` + `MediaQuery.of` 全量依赖 | **属实**。`note_list_items.dart` build 顶部确认。键盘收起（ScrollStart 里 unfocus）→ MediaQuery 变化 → 整页含 ListView 重建。搜索后首滑顿挫的合理来源之一 |
| 4 | ScrollEnd 一帧堆积：`isListScrolling.value=false` 集中放行图片解码 + loadMore + anomaly 检查 | **属实**。anomaly 检查已移出热路径但仍在 ScrollEnd 同帧；图片解码集中放行是"停下那一顿"的合理来源 |
| 5 | 滚动 session 性能采集无开关保护、`_noteListPerfKindFor` 每 build 三次全文扫描 | **不成立（已过时）**。`_startScrollSessionPerfCapture` 首行即检查 `_firstOpenScrollPerfEnabled`（= developerMode && 专用开关）；`_recordNoteListItemBuild` 未录制时提前返回。但提醒：测卡顿时**务必确认该开关关闭** |
| 6 | 每 item 常驻重包装层：Stack+InkWell 导出层（99% 时间死重）+ AnimatedOpacity + AnimatedSize（每 item 常驻 ticker + 每次 layout 额外测量） | **属实，有价值**。`note_list_items.dart` itemBuilder 确认全部无条件包裹。是首滑/惯性时新 item 构建成本的放大器 |
| 7 | keepAlive 窗口随滚动中心漂移，build 期间读 scrollController.position，滚动中 keepAlive 翻转造成 element 挂/摘抖动 | **属实**。`_shouldKeepAliveNoteListItem` 调用 `_estimatedScrollCenterIndex()` 确认 |
| 8 | BackdropFilter 光栅压力 | 已知（06-13 实测 raster 95.7ms→10.2ms），维持"不在滚动中开关模糊"的历史结论，实验开关已可让用户自行取舍 |

**综合判断**：主因仍是 QuillEditor 首次布局（有实测钉死）；Gemini 的 #6、#7、#3、#4 为**真实的叠加放大因素**，其 #1、#5 两条"高优先级"指控不成立，勿据其返工。

### 三、分步优化计划（按序实施，每步独立验证，不达标即回退）

**验证方法统一**：真机 release/profile 模式、关闭性能监控开关，用现有 scroll session 日志对比
`worstBuild` / `itemLayout.worst` / `slowLayouts` 前后差异；每步独立提交。

1. **Step 1（核心，零视觉变化）— 折叠态富文本喂截断 Document**：
   折叠态只显示 160px 但 QuillEditor 布局整篇文档。改为按 `_estimateDeltaHeight` 截取约 2 倍
   折叠高度的前若干 ops 构造截断 Document 交给 QuillEditor 布局。渲染引擎不变、像素级一致
   （160px 以下本就被 ClipRect 裁掉）；展开态是独立缓存变体（`resolveVariant` 已区分），
   用完整文档，互不影响。"加粗优先"已有折叠态改写文档先例。
   预期：长笔记首次布局大幅下降；对短富文本无效（由 Step 2 补）。
2. **Step 2 — item 包装层按需化**：
   导出 Stack+Material+InkWell 层仅 `_isExportMode` 时叠加；删除动画的
   AnimatedOpacity+AnimatedSize+Align 仅删除流程涉及的 item 包裹
   （注意处理动画首帧：包裹后延迟一帧再驱动收起，保证删除动画不丢）。
   去掉每 item 常驻 ticker 与 AnimatedSize 的逐帧尺寸测量。正常态视觉零变化。
3. **Step 3 — keepAlive 改固定策略**：
   仅媒体 item（现有 `shouldKeepAliveQuoteItem`）与短列表 keepAlive，
   移除随滚动中心漂移的 ±18 窗口及 build 期间读 scroll position。
4. **Step 4 — 收窄依赖 + ScrollEnd 削峰**：
   `MediaQuery.of` → `sizeOf`/`paddingOf`；`Provider.of<NoteSearchController>` →
   `context.select` 仅订阅 `searchError`；tagMap/rowIndexByKey 缓存为字段随 `_quotes` 失效；
   ScrollEnd 的图片解码放行延迟 1~2 帧分批。
5. **Step 5（仅当 Step 1-4 后短富文本首滑尖峰仍不达标）— 轻量只读渲染器**：
   即 06-13 原计划的 Delta→TextSpan 方案。因造轮子成本与视觉还原风险，列为最后手段，
   实施前必须先有截图对照测试。

**不做**：滚动中开关模糊（历史证明负优化）、全量 keepAlive（06-13 已废弃）、
重复"修复"Gemini #1/#5（已核实不成立）。

---

## 2026-07-02: Step 1 实测结果 + Step 5 搁置 + Step 2/4 实施决定

**决策者**: 上晋 + Claude Fable 5（GitLab Duo Chat）
**类型**: 实测复盘 / 计划调整

### Step 1（截断 Document，commit `8ac2508c`）真机实测结果

用户真机日志（session scroll-4 首滑下 / scroll-7 回滑上，105 条中 rich=39, media=31）：

| 指标 | 首滑(down) | 回滑(up) | 历史基线(06-13) |
|---|---|---|---|
| itemLayout.worst | **28.0ms** (rich-image) | 3.7ms (plain) | 39~67ms (rich) |
| 纯 rich 首布局 | 11~12.5ms | — | 10~22ms 常见, 最高 67 |
| worstBuild | 180.7ms | 9.0ms | 88~145ms |
| frameJank | 14 | **0** | — |

**结论**:
1. 截断**有效**：单卡首布局峰值 67→28ms。但用户体感无变化，原因是**扎堆**：
   slowLayouts 显示 index 75~87 区段 6 张 rich-image 卡各 20~28ms，合计 139.5ms，
   与 worstBuild 180.7ms 对应。图片密集区连续进入 cacheExtent 时多卡首布局挤进相邻帧。
2. 截断后 20~28ms 的剩余成本主体是 **QuillEditor 固定开销 + 图片 embed 脚手架布局**，
   与文档长度无关（06-13 复核中"可能 1"被证实）。
3. 回滑 session frameJank=0、全部 plain 3ms 级，证明现有 keepAlive + 缓存下回访路径已达标。
4. 顺带发现：imageCache 29 张图 82.3MB（均 2.8MB/张），embed 图片解码未限制尺寸，
   后续应加 `cacheWidth`（内存问题，与滚动卡顿无关）。
5. 关于数据可信度：单次 session 有方差，但两 session 模式与历史数据一致，
   且缓存计数器为精确计数非采样，方向性结论可靠。

### 计划调整

- **Step 5（轻量只读渲染器）搁置**：用户判断视觉还原风险与长期维护成本过高。
  记录在案：若未来重启，剩余 20~28ms 的固定开销只能靠它消除，届时应限定"仅折叠态、
  仅 160px 窗口内容"以缩小还原面。
- **Step 3（keepAlive 固定策略）取消**：实测回滑 frameJank=0，现策略已达标；
  keepAlive 翻转仅发生在整列表重建时（本次 session buildΔ=1，罕见），
  Gemini #7 的"滚动中反复挂/摘"被高估。改动反而有富文本回访重新变卡的回归风险。
- **Gemini #2（tagMap/rowIndexByKey 缓存）取消**：微秒级收益 vs 过期缓存风险，不值。
- **立即实施 Step 2 + Step 4**（本次提交）：
  1. 导出 InkWell 覆盖层仅 `_isExportMode` 时加入 Stack children
     （保留常驻 Stack 壳避免 item 子树重挂载）；
  2. 删除动画改为按需挂载的自驱动 `_NoteDeleteCollapse`
     （FadeTransition+SizeTransition，250ms easeInCubic，视觉等价），
     去掉每 item 常驻的 AnimatedOpacity+AnimatedSize ticker 与逐帧尺寸测量；
  3. `MediaQuery.of` → `sizeOf`/`paddingOf`，避免键盘弹收触发整页重建；
  4. `Provider.of<NoteSearchController>(listen:true)` → `context.select` 仅订阅 searchError；
  5. ScrollEnd 的 `isListScrolling=false`（图片解码放行）与 anomaly 检查延迟约 2 帧
     （Timer 32ms + generation 防过期覆盖），不与 ScrollEnd 帧的 loadMore 挤同一帧。

**预期与验收**：Step 2/4 是削固定成本与削峰，预计缓解但不根除 rich-image 扎堆尖峰
（根除需 Step 5）。验收同前：真机对比 worstBuild / frameJank / eventWorst。
