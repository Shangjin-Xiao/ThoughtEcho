## 9. 每日一言多语言 API 规划（2026-03）

### 9.1 目标与约束
- 在不大改现有“每日一言”架构的前提下，为应用增加中文之外的 quote provider 支持。
- 保留现有 `hitokotoType`、默认分类/默认标签、双击保存、离线回退和本地“每日一言”逻辑。
- 统一继续输出当前 UI 和保存流程已依赖的数据结构：
  - `content`
  - `source`
  - `author`
  - `type`
  - `from_who`
  - `from`

### 9.2 现有实现中的关键耦合点
- `lib/services/api_service.dart` 当前直接绑定 Hitokoto，并将响应归一化为兼容结构。
- `lib/models/app_settings.dart` 使用 `hitokotoType` 保存逗号分隔的内部类型码。
- `lib/pages/home_page.dart` 和 `lib/widgets/add_note_dialog.dart` 会根据 `type` 把每日一言保存到固定默认分类 ID。
- `lib/services/database_service.dart` 初始化固定默认分类；`lib/services/database_health_service.dart` 的本地回退还依赖分类名 `每日一言`。
- `lib/widgets/daily_quote_view.dart` 默认按 `——作者 《出处》` 渲染来源，所以新的 provider 最好至少返回作者，出处没有时要允许空值优雅降级。

### 9.3 候选 API 对比

| Provider | 语言/范围 | 随机能力 | 分类/标签过滤 | 关键字段 | 鉴权 | 大陆可用性判断 | 适配结论 |
|---|---|---|---|---|---|---|---|
| Hitokoto | 中文为主 | 强 | 强，`c=` 多分类 | `hitokoto/from/from_who/type` | 无 | 最优 | 继续作为中文默认源 |
| Quotable | 英文 | 强，`/quotes/random` | 强，`tags/author/length` | `content/author/tags[]` | 无 | ❌ **2024-09 起域名已停止解析，API 不可用**（GitHub #253） | ~~最适合做首个英文公共 provider~~ → 已死，改用 QuoteSlate 替代 |
| API Ninjas Quotes | 英文 | 强，`/v2/randomquotes` | 强，20 分类 + author/work | `quote/author/work/categories[]` | `X-Api-Key`（免费层仅限非商业） | ✅ 存活，P50=427ms，99.99% SLA；免费 1 条/次，付费最多 100 条 | 最完整英文增强源，有 `work` 出处字段 |
| TheySaidSo | 英文为主，QOD 场景强 | 有，但随机/搜索多为私有能力 | 有，QOD 分类 + 搜索分类/作者/长度 | `quote/author/tags/category/language/date/permalink` | ⚠️ **已关闭匿名访问**，免费也需注册 Token（`X-TheySaidSo-Api-Secret`），10 次/小时 | 海外服务；直连 `qod/random/search` 均 401（设计如此） | 优先级低：需 Key + 限流严格 |
| Forismatic | 英/俄 | 有 | 弱 | `quoteText/quoteAuthor` | 无 | ✅ 存活但**本质弃置软件**：无维护、页面有垃圾广告、语料池小、有 CORS 问题 | 不建议：可能随时消失，无 SLA |
| Animechan | 动漫台词 | 强 | 按 `anime/character` | `quote/anime/character` | ⚠️ 已迁移至 `api.animechan.io/v1`，旧 URL 废弃；免费仅 **5 次/小时** | ✅ 100% 近 90 天 uptime，1.4k stars 活跃维护 | 适合动漫垂直 provider，但限流极严 |
| FavQs | 英文 | 有 | ✅ tags + 投票 + 收藏 | `quote/author/tags[]/favorites_count` | QOTD 无需 Key；搜索/列表需免费 Token；30 req/20s | ✅ 存活 | ⭐ 元数据最丰富（社区投票/收藏），适合精选内容场景 |
| ZenQuotes | 英文 | 有，可批量拉 50 条 | 免费无 / 付费有 keywords | `q/a/i (quote/author/image)` | 无需 Key；**5 req/30s** + 必须署名 | ✅ 存活，已服务 2.23 亿+ 请求 | ⭐ 人工精选 3237 条，质量高；批量缓存策略友好 |
| DummyJSON | 英文样例 | 有 | ❌ 无 | `quote/author`（仅两字段） | 无 | ✅ 存活 | ❌ **仅 100 条**，大写异常，仅适合测试/原型 |

### 9.4 TheySaidSo 详细判断
- 官方文档：`https://theysaidso.com/api/?shell`
- 文档能力：
  - `GET /qod(.json)`：按 `category` 获取每日一句
  - `GET /qod/categories.json`：获取 QOD 分类
  - `GET /quote/random.json`：随机 quote
  - `GET /quote/search.json`：按 `category`、`author`、`minlength`、`maxlength` 检索
- 官方文档示例返回：
  - `quote`
  - `author`
  - `tags[]`
  - `category`
  - `language`
  - `date`
  - `permalink`
  - `id`
  - `background`
  - `title`
- 优势：
  - 比普通 quotes API 更像“内容平台”，带有 QOD 分类、图片背景和 permalink。
  - 如果后续想要做“今天固定一句 + 配图分享”，扩展潜力不错。
- 问题：
  - 没有 `work/source` 字段，不如 API Ninjas 贴合当前 UI 的出处展示。
  - 文档明确提醒公共客户端不要直接暴露 API Key；对于 Web 端尤其不友好。
  - 免费公开限流低（文档写 10 次/小时），随机/搜索能力更依赖 API Key。
  - 当前环境直连 `https://quotes.rest/qod?category=inspire`、`/quote/random.json`、`/quote/search.json` 都返回 `401`，因此实际接入前必须再做真实终端验证。
- 结论：
  - **如果目标是“固定的 Quote of the Day”**，TheySaidSo 值得保留为可选 provider。
  - **如果目标是“尽量贴近现在可刷新、可随机、无感切换的一言体验”**，它优先级低于 Quotable 和 API Ninjas。

### 9.5 实现多 provider 的三种方案

#### 方案 A：最小改动的 provider 适配层（推荐）
1. 在设置中新增 `dailyQuoteProvider`、`dailyQuoteLanguage`（或 `dailyQuoteLocale`）。
2. 保留 `hitokotoType` 作为应用内部稳定分类码。
3. 在 `ApiService` 前增加 provider adapter，将各家响应归一化为当前结构。
4. 当第三方不支持分类或缺少出处时，用内部默认映射兜底。

**优点**
- 改动面最小。
- 不破坏默认标签设计。
- `home_page.dart` / `add_note_dialog.dart` 基本可不动。

**缺点**
- 需要维护 provider 能力差异映射。

#### 方案 B：能力驱动的 provider 配置层
1. 为每个 provider 定义能力描述：是否支持随机、QOD、分类、作者过滤、出处字段、API Key。
2. 设置页根据 provider 能力动态展示可用选项。
3. 请求层根据能力降级。

**优点**
- 可扩展性好，后续接更多 provider 时更清晰。

**缺点**
- UI 和设置逻辑改动比方案 A 略大。

#### 方案 C：统一后端/自托管聚合层
1. 服务端统一接多个外部 provider。
2. 客户端永远请求自己的统一接口。
3. 在服务端处理 API Key、速率限制、缓存与大陆可达性。

**优点**
- 线上可控性最佳。
- 对大陆访问和第三方 API 波动最友好。

**缺点**
- 明显超出当前“少改设计”的范围。
- 需要额外部署和维护成本。

### 9.6 推荐路线
1. **第一阶段**：继续保留 Hitokoto，新增 **QuoteSlate** 作为首个英文公共 provider（Quotable 已于 2024-09 停服）。
2. **第二阶段**：新增 API Ninjas 作为“更完整但需要 Key”的英文增强 provider。
3. **第三阶段**：如果产品要强调“每日固定一句”或配图分享，再新增 TheySaidSo 作为可选 QOD provider。
4. **第四阶段**：视大陆访问和稳定性情况，预留自托管/镜像能力。

### 9.7 推荐的内部映射原则
- 不把第三方原始 tag/category 直接写入 `type`。
- `type` 始终映射回应用内部稳定类型码（优先沿用 `a-k/l`）。
- 无法可靠映射时，回退到用户当前已选类型中的首个类型码。

示例：
- Hitokoto：继续用原始 `type`
- Quotable：`philosophy/wisdom -> k`，`poetry -> i`，其他无法稳定映射时回退
- API Ninjas：`philosophy -> k`，`art/writing -> d`，`humor -> l`
- TheySaidSo：`inspire/life/management/funny` 等先映射到最接近的内部类型；若无法稳定映射则回退到首选类型码
- Animechan：固定映射 `a`

### 9.8 预计改动面
**需要改动**
- `lib/models/app_settings.dart`
- `lib/services/settings_service.dart`
- `lib/services/api_service.dart`
- `lib/pages/hitokoto_settings_page.dart`
- `lib/l10n/app_zh.arb`
- `lib/l10n/app_en.arb`

**尽量不动**
- `lib/pages/home_page.dart`
- `lib/widgets/add_note_dialog.dart`
- `lib/services/database_service.dart`
- `lib/services/database_health_service.dart`

### 9.9 扩展 API 搜索结果（2026-03 补充）

#### 9.9.1 新增英文 API

| Provider | URL | 免费/Key | 随机端点 | 分类过滤 | 关键字段 | 限流 | 可用性 | 评价 |
|---|---|---|---|---|---|---|---|---|
| **QuoteSlate** ⭐ | `quoteslate.vercel.app` | 免费，无 Key | `GET /api/quotes/random` | ✅ tags, authors, minLength/maxLength | `quote, author, tags[]` | 100 req/15min/IP | ⚠️ Vercel 安全检查可能阻断 curl，浏览器/移动端正常 | 最佳新免费选择，开源可自部署（2600+ 条） |
| **Stoic Quotes** | `stoic-quotes.com` | 免费，无 Key | `GET /api/quote` | ❌ 仅斯多噶学派 | `text, author` | 无显式限制 | ✅ 已验证存活 | 哲学垂直源，字段少但稳定 |
| **Motivational Spark** | `motivational-spark-api.vercel.app` | 免费，无 Key | `GET /api/quotes/random` | ❌ | `author, quote` | 无 | ✅ 100% 可用性监控 | 最简备用源 |
| **ZenQuotes** | `zenquotes.io` | 免费层无 Key | `GET /api/random` 单条 / `/api/quotes` 50 条批量 | 免费无 / 付费有 keywords | `q (quote), a (author), i (image)` | 免费 5 req/30s | ✅ 已服务 2.23 亿+ 请求 | 需署名；批量拉取可缓存；3237 条 |
| **PaperQuotes** ⭐ | `api.paperquotes.com` | 需 Key（Token） | `GET /apiv1/quotes/?language=en&limit=5` | ✅ tags 过滤 | `quote, author, tags[], likes, language` | 免费 500 次/月 | ✅ 99.9% uptime | **560 万+ 条**，15 种语言，多语言最强 |

#### 9.9.2 日语 API

| Provider | URL | 免费/Key | 随机端点 | 关键字段 | 可用性 | 评价 |
|---|---|---|---|---|---|---|
| **名言教えるよ** ⭐ | `meigen.doodlenote.net` | 免费，无 Key | `GET /api/json.php?c=1`（1–10 条随机） | `meigen (名言), auther (作者，注意拼写)` | ✅ 活跃 | **唯一发现的日语免费 REST API**，字段简单可映射 |
| **Kotowaza npm** | `github.com/sepTN/kotowaza` | 免费 MIT | 本地 JS `kotowaza.random()` | `japanese, reading, romaji, meaning.en, tags, jlpt` | ✅ npm 活跃 | 非 REST API，是 JSON 数据集；含假名/JLPT/英译，适合打包本地 |

> **Hitokoto** 虽名为"一言"（日语词），但内容全为**中文**，不含日语内容。

#### 9.9.3 韩语 API

| Provider | URL | 免费/Key | 随机端点 | 关键字段 | 可用性 | 评价 |
|---|---|---|---|---|---|---|
| **Korean Advice API** ⭐ | `korean-advice-open-api.vercel.app` | 免费（非商业） | `GET /api/advice` | `author, authorProfile, message` | ✅ Vercel 托管，17 stars | 最佳韩语名言源，100+ 条 |
| **行복 명언 API** | `api.sobabear.com` | 免费 | `GET /happiness/random-quote` | `content (韩+英双语), author` | ✅ 2024 年 9 月发布 | 每日轮换（非每次随机），含英文翻译 |
| **Klassic Quote** | `klassic-quote-api.mooo.com` | 免费 MIT | `GET /v1/random-quote` | `author, quote, name (电影名)` | ✅ 21 stars | 韩国电影台词，**可能含脏话**，不适合励志场景 |
| **kadvice npm** | `github.com/chkim116/kadvice` | 免费 MIT | 本地 JS `kadvice.getOne()` | `author, authorProfile, message, tag (1=삶, 2=동기부여, 3=기타)` | ✅ | 非 REST API，JSON 数据集，可提取打包 |

#### 9.9.4 法语 / 多语言 API

| Provider | URL | 支持语言 | 免费/Key | 随机端点 | 关键字段 | 评价 |
|---|---|---|---|---|---|---|
| **PaperQuotes** ⭐ | `api.paperquotes.com` | 15 种语言（含 FR/DE/ES/IT） | 需 Key，免费 500 次/月 | `GET /apiv1/quotes/?language=fr&tags=love` | `quote, author, tags[], language` | 多语言最强，560 万+ 条 |
| **gpalleschi/quotes_api** | `quotes-api-three.vercel.app` | IT 🇮🇹 / EN 🇬🇧 / ES 🇪🇸 | 免费，无 Key | `GET /api/randomquote?language=it` | `quote, author, tags` | 开源可自部署，~1746 英文条目 |

> 未发现专门的法语/德语免费公共 API。PaperQuotes 是唯一覆盖法语/德语的选择。对于离线优先场景，建议打包本地 JSON 数据集作为补充。

#### 9.9.5 综合对比矩阵

| API | 中 🇨🇳 | 英 🇬🇧 | 日 🇯🇵 | 韩 🇰🇷 | 法 🇫🇷 | 免费 | 无 Key | 分类 | 作者 | 出处/作品 | 可自部署 |
|-----|--------|--------|--------|--------|--------|------|--------|------|------|-----------|----------|
| Hitokoto | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ 11类 | ✅ | ✅ | ✅ |
| QuoteSlate | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ tags | ✅ | ❌ | ✅ |
| API Ninjas | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ 20类 | ✅ | ✅ work | ❌ |
| PaperQuotes | ❌ | ✅ | ❌ | ❌ | ✅ | 500/月 | ❌ | ✅ tags | ✅ | ❌ | ❌ |
| ZenQuotes | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | 付费 | ✅ | ❌ | ❌ |
| 名言教えるよ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| Korean Advice | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| Stoic Quotes | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| gpalleschi | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ tags | ✅ | ❌ | ✅ |

### 9.10 现有代码接入复杂性分析

#### 9.10.1 数据流全景

```
AppSettings.hitokotoType (逗号分隔类型码 "a,b,c")
    ↓
DailyQuoteView._loadDailyQuote()
    ↓
ApiService.getDailyQuote(l10n, type)     ← 唯一的 API 调用点
    ↓ (响应归一化为内部 Map)
{ content, source, author, type, from_who, from }   ← 内部数据契约
    ↓
DailyQuoteView 渲染 → 双击触发 onAddQuote
    ↓
home_page._showAddQuoteDialog(content, from_who, from, fullMap)
    ↓
AddNoteDialog(hitokotoData: fullMap) → _addDefaultHitokotoTagsAsync()
    ↓
保存为 Quote，自动分配标签 + 分类
```

#### 9.10.2 各文件耦合度

| 文件 | 耦合度 | 需改动 | 说明 |
|---|---|---|---|
| `api_service.dart` | 🔴 高 | ✅ 主要改动点 | 硬编码 `v1.hitokoto.cn` URL + hitokoto 特定响应解析 |
| `hitokoto_settings_page.dart` | 🔴 高 | ✅ 需扩展 | 类型选择 chip 完全绑定 hitokoto 分类 |
| `add_note_dialog.dart` | 🟡 中 | ⚠️ 小幅改动 | `_hitokotoTypeToCategoryIdMap` + `_convertHitokotoTypeToTagName()` 需对未知 provider 类型降级 |
| `app_settings.dart` | 🟢 低 | ✅ 加字段 | 新增 `quoteProvider` 字段，~5 行 |
| `daily_quote_view.dart` | 🟢 低 | ❌ 不动 | **完全依赖归一化 Map**，对 provider 透明 |
| `home_page.dart` | 🟢 低 | ❌ 不动 | 透传数据，不解析 provider 细节 |
| 离线回退机制 | 🟢 低 | ❌ 不动 | provider 无关 |
| SmartPush 集成 | 🟢 低 | ❌ 不动 | 已使用相同归一化格式 |

#### 9.10.3 核心发现：双击保存流程可完全复用

**关键洞察**：`DailyQuoteView`、`AddNoteDialog`、`home_page.dart` 全部依赖的是**归一化后的内部 Map** `{content, source, author, type, from_who, from}`，而非 hitokoto API 本身。这意味着：

- ✅ 双击一言 → 添加笔记的完整流程**零改动**
- ✅ 自动创建"每日一言"标签的机制**零改动**
- ⚠️ 仅需在 `add_note_dialog.dart` 中对非 hitokoto 的 `type` 值做**优雅降级**（跳过类型子标签或使用通用标签），约 10 行

#### 9.10.4 最小改动方案（方案 A 细化）

| 步骤 | 文件 | 改动量 | 内容 |
|---|---|---|---|
| 1 | `app_settings.dart` | ~5 行 | 新增 `quoteProvider` 字段，默认 `'hitokoto'` |
| 2 | `settings_service.dart` | ~10 行 | 持久化 `quoteProvider` |
| 3 | `api_service.dart` | ~50 行 | `getDailyQuote()` 按 provider 分发；提取 `_fetchFromHitokoto()`，新增 `_fetchFromQuoteSlate()` 等；各 provider 归一化到相同内部 Map |
| 4 | `hitokoto_settings_page.dart` | ~20 行 | 顶部加 provider 选择器；类型 chip 仅在 provider=hitokoto 时显示 |
| 5 | `add_note_dialog.dart` | ~10 行 | `_addDefaultHitokotoTagsAsync()` 对未知 type 降级：始终添加"每日一言"标签，未知类型跳过子标签 |
| 6 | `l10n/*.arb` | ~15 行 | provider 名称的国际化文案 |
| **合计** | | **~110 行** | **0 个 UI 重构，0 个破坏性变更** |

### 9.11 更新后的推荐路线

1. **第一阶段**（最小可用）：
   - 保留 Hitokoto（中文默认）
   - 新增 **QuoteSlate**（英文，免费无 Key，可自部署）
   - 新增 **名言教えるよ**（日语，免费无 Key）
   - 改动量 ~110 行，复用现有双击保存逻辑

2. **第二阶段**（增强）：
   - 新增 **API Ninjas**（英文增强，需 Key，有 `work` 出处字段）
   - 新增 **Korean Advice API**（韩语，免费无 Key）
   - 新增 **PaperQuotes**（法/德/西/意多语言，需 Key，免费 500 次/月）

3. **第三阶段**（离线增强）：
   - 打包 **Kotowaza JSON**（日语谚语离线数据集）
   - 打包 **kadvice JSON**（韩语名言离线数据集）
   - 打包社区法语/德语名言数据集
   - 对于本地优先应用特别合适

4. **第四阶段**（进阶可选）：
   - AI 翻译回退：利用已有 AI 服务将英文名言按用户语言翻译
   - TheySaidSo 作为 QOD 可选源
   - 自托管/镜像能力

### 9.12 各 provider 归一化映射示例

```dart
// QuoteSlate → 内部 Map
{ 'content': json['quote'], 'source': '', 'author': json['author'],
  'type': _mapTagsToInternalType(json['tags']), 'from_who': json['author'], 'from': '' }

// 名言教えるよ → 内部 Map
{ 'content': json['meigen'], 'source': '', 'author': json['auther'],  // 注意原 API 拼写
  'type': 'k', 'from_who': json['auther'], 'from': '' }

// Korean Advice API → 内部 Map
{ 'content': json['message'], 'source': '', 'author': json['author'],
  'type': 'k', 'from_who': json['author'], 'from': json['authorProfile'] ?? '' }

// PaperQuotes → 内部 Map
{ 'content': json['quote'], 'source': '', 'author': json['author'],
  'type': _mapTagsToInternalType(json['tags']), 'from_who': json['author'], 'from': '' }

// ZenQuotes → 内部 Map
{ 'content': json['q'], 'source': '', 'author': json['a'],
  'type': 'k', 'from_who': json['a'], 'from': '' }
```

### 9.13 测试与验收重点
- 各 provider 响应的统一归一化测试
- 类型码映射测试（已知类型 + 未知类型降级）
- provider 失败 → 本地笔记 → 默认文案的回退链测试
- 设置迁移测试，确保不破坏现有 `hitokotoType`
- 双击每日一言保存后的默认分类/默认标签落库回归测试
- 多 provider 切换后设置持久化验证
- 日/韩/法语 provider 在大陆网络环境下的可达性实机测试

### 9.14 最终确定的多语言 API 接入清单与实施计划

基于 API 稳定性、连通性及内容质量的测试，最终确定采用“用户自选+详细提示”的策略。以下是首批接入的公共免费 API：

#### 9.14.1 目标 API 矩阵

| 标识符 | 语言 | 界面显示名称 | 接口特点说明 |
| :--- | :--- | :--- | :--- |
| `hitokoto` | 🇨🇳 中文 | **一言 (Hitokoto)** | *(默认)* 最经典的中文短句接口，支持动画、文学、哲学等细分类别。 |
| `zenquotes` | 🇬🇧 英文 | **ZenQuotes** | 提供 3000+ 高质量的人工精选英文名言，内容深刻，每次刷新随机获取。 |
| `theysaidso` | 🇬🇧 英文 | **They Said So** | 全球最大的名言库之一，内容极度丰富。（注：免费版有每小时 10 次的刷新限制） |
| `dummyjson` | 🇬🇧 英文 | **DummyJSON** | 极其稳定且快速的随机名言源，包含约 1400 条经典名言。 |
| `favqs` | 🇬🇧 英文 | **FavQs (QotD)** | 真正的“每日一言”，每天只更新一次内容，不随刷新改变。 |
| `stoic` | 🇬🇧 英文 | **Stoic Quotes** | 专注于斯多噶哲学流派（如马可·奥勒留、塞内卡等）的深刻语录。 |
| `meigen` | 🇯🇵 日文 | **名言教えるよ** | 纯正的日文名言警句接口，每次刷新随机获取。 |
| `kadvice` | 🇰🇷 韩文 | **Korean Advice** | 优质的韩文名言与人生建议，包含作者与出处信息。 |

#### 9.14.2 具体实施步骤（4 步安全落地）

1. **数据层配置 (`app_settings.dart` & `settings_service.dart`)**
   - 引入 `quoteProvider` 字段，默认值为 `hitokoto`，支持本地持久化。
2. **网络层适配 (`api_service.dart`)**
   - 增加包含上述 API 的配置表和工厂方法。
   - 重构 `getDailyQuote()`，根据当前选中的 provider 发送对应网络请求。
   - 响应全部归一化为 `{content, author, source, type, from_who, from}`。对于非 Hitokoto 的 API，`type` 字段赋予通用兜底值（如 `'other'`），以触发后续的平滑降级。
3. **UI 层：设置页面改造 (`hitokoto_settings_page.dart`)**
   - 页面顶部增加精美选择器，列出所有 Provider 及对应的“特点说明”。
   - 联动隐藏逻辑：仅当选中的是“一言 (Hitokoto)”时，下方才展示具体的细分类别勾选面板。
4. **UI 层：标签多语言展示兼容 (`add_note_dialog.dart`, `quote_item_widget.dart` 等)**
   - 维持数据库中写死的 `'每日一言'` 标签不变。
   - 在 UI 渲染节点，判断若标签名为 `'每日一言'`，则直接映射为多语言文案 `l10n.featureDailyQuote`。
   - 保存时的类型降级：针对非 Hitokoto API 的兜底类型（如 `'other'`），程序在双击保存时仅添加基础的“每日一言”标签，跳过诸如“#动画”、“#文学”等子类型标签的填充。
