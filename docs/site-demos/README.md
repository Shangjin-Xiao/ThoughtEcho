# Thoughter 介绍页 · 风格提案（2026-08-11）

五个方向的可点击 demo，用于选型。选定后再按选中的方向做成正式页面
`res/thoughter.html`，并从主站导航接入。

这些文件只是提案稿，**不在 `res/` 下，不会随主站部署**。

## 五个方向

| 文件 | 方向 | 一句话 | 冒的险 |
|---|---|---|---|
| `thoughter-a-paper.html` | 纸与墨（主站同源） | Thoughter 的话全部退到页边空白，正文永远是你的 | 真的把版式做成"正文栏 + 批注栏"，而不是把批注做成装饰 |
| `thoughter-b-lab.html` | 研究实验室 / 模型卡 | 不推销，只交代规格；首屏直接给一段真实运行轨迹 | 首屏没有卖点，只有一张 trace |
| `thoughter-c-stage.html` | 舞台 / 发布会 | 黑幕、巨型字、一句话一屏、滚动揭示 | 单一暗色世界，不做浅色 |
| `thoughter-d-press.html` | 活字 / 版画排印 | 一份关于 Thoughter 的杂志内页 | 中文竖排作为版式骨架、朱砂印、墨版反白 |
| `thoughter-e-glassbox.html` | 玻璃箱 / 可操作现场 | 整页就是 Thoughter，左边对话右边机器视角 | 论点即形式——"透明"只能演不能讲 |

## 共同的内容底稿

五份稿子讲的是同一批事实，都来自代码而非想象：

- 十个工具，七个只读（`lib/services/agent_tools/`）
- 提案制：`propose_note_create` / `propose_note_edit` 只出提案，每轮最多一个，
  修改走 `document_revision` 校验
- 两层长期记忆：画像层每轮自动注入，事实层靠 `recall` 按需检索，可关可删
- 归属区分：`author` / `source` 决定"他写的"还是"他摘的"
- 不编造位置天气；笔记与网页内容按不可信数据处理
- 本地优先，自备 API Key，不配也不影响其他功能

## 技术备注

- demo 未使用 Web 字体（预览环境禁外链），全部走系统字体栈；
  正式页可沿用主站已有的 Google Fonts。
- `thoughter-c-stage.html` 内嵌了 `res/screenshot/note_qa_chat_page.jpg`（base64）。
  该截图里的抬头仍是旧版"AI 助手"，正式上线前需换成 Thoughter 的新截图。
- D 的竖排依赖字体的纵向度量。Windows / macOS / Android 的中文字体正常；
  只装了 WenQuanYi 的 Linux 环境会重叠（`.song` 字体栈已把它排在最后）。
- 五份都实现了浅色 / 深色 / 跟随系统三态，并已通过标签闭合与横向溢出检查。

## 定稿后要做的事

1. 产出 `res/thoughter.html`，复用 `res/style.css` 的变量与中英切换机制
2. 主站 `res/index.html` 导航与功能区加入口
3. `res/sitemap.xml` 增加条目，`res/vercel.json` 视需要加 `/thoughter` 短路径
4. 补 OG / Twitter meta 与 JSON-LD
