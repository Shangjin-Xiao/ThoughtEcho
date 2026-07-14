## 2024-05-24 - [ClipboardService 硬编码提取]
**发现:** 发现剪贴板内容，点击添加为笔记, 笔记已保存, 操作失败
**规则:**
- `发现剪贴板内容，点击添加为笔记` -> `clipboardFoundHint` (Clipboard content found, tap to add as note)
- `笔记已保存` -> `noteSaved` (已存在于系统，直接复用)
- `操作失败` -> `operationFailed` (Operation failed)
遵循极简风格，使用清晰明了的词汇。
## 2024-05-25 - [笔记编辑器硬编码提取]
**发现:** 编辑器界面的「编辑元数据」、「正在保存」、「完成」、「文档加载失败，请重新打开编辑器」、「正在加载大型文档...」、「此笔记首次保存时未记录位置和天气信息」
**规则:**
- `编辑元数据` -> `editMetadata` (Edit Metadata)
- `正在保存` -> `savingNote` (Saving)
- `完成` -> `done` (Done)
- `文档加载失败，请重新打开编辑器` -> `documentLoadFailed` (Document load failed, please reopen the editor)
- `正在加载大型文档...` -> `loadingLargeDocument` (Loading large document...)
- `此笔记首次保存时未记录位置和天气信息` -> `noLocationWeatherRecorded` (Location and weather were not recorded when this note was first saved)
优先使用现存键值复用，遵循极简风格翻译。
## 2024-05-25 - [提取笔记编辑器界面的硬编码中文字符串]
**发现:** 编辑器界面存在的多处硬编码文本：「编辑元数据」、「正在保存」、「完成」、「文档加载失败，请重新打开编辑器」、「正在加载大型文档...」、「此笔记首次保存时未记录位置和天气信息」
**规则:**
- 寻找现存翻译键值复用，例如：`editMetadata`, `savingNote`, `done`, `documentLoadFailed`, `loadingLargeDocument`。
- 对于缺失项，新增 `noLocationWeatherRecorded` 到各语言 `arb` 文件，并遵循极简规范。
## 2024-05-25 - [提取手动API密钥测试页面的硬编码中文字符串]
**发现:** 手动API测试页面存在的多处硬编码文本：「手动API密钥测试」、「直接输入API参数进行测试，绕过存储系统检查API密钥是否有效。」、「错误: 请填写所有必填字段」、「=== 手动API密钥测试报告 ===」、「测试参数:」、「密钥格式检查:」、「发送请求:」、「响应结果:」
**规则:**
- 寻找现存翻译键值复用，并遵循极简规范。
- 对于缺失项，新增 `manualApiTestTitle`, `manualApiTestDesc`, `testResultLabel`, `fillAllFieldsError`, `testReportTitle`, `testParamsLabel`, `keyFormatCheckLabel`, `sendRequestLabel`, `responseResultLabel` 到各语言 `arb` 文件。
## 2024-05-26 - [提取编辑器 AI 助理特性的硬编码中文字符串]
**发现:** 编辑器 AI 助理特性（`editor_ai_features.dart`）界面中的硬编码文本：`应用更改` 和 `附加到原文`
**规则:**
- 将 `应用更改` 替换为现存键值 `applyChanges`
- 对于缺失项，新增 `appendToOriginal` (Append to Original) 到各语言 `arb` 文件，并遵循极简规范翻译。
## 2026-05-25 - [HitokotoWidget 提取硬编码]
**发现:** HitokotoWidget 中存在 "每日一言" 和 "加载中..." 硬编码
**规则:** 分别替换为 featureDailyQuote 和 loading。
## YYYY-MM-DD - [提取 WebDAV 同步冲突处理相关的硬编码字符串]
**发现:** WebDAV 同步页面冲突处理的提示：`"确认保留（移入默认分类）"`, `"已确认并移回默认笔记列表。"`, `"丢弃此冲突备份"`, `"已永久丢弃此冲突笔记。"`
**规则:** 采用极简风格翻译，例如 `webdavConflictKeepTooltip`, `webdavConflictKeepSuccess`, `webdavConflictDiscardTooltip`, `webdavConflictDiscardSuccess`
## 2026-06-22 - [提取 WebDAV 同步页面硬编码字符串]
**发现:** WebDAV 同步页面硬编码："已关闭 WebDAV 云同步。本地数据完全保留。", "关闭并停用云同步", "去处理", "没有检测到冲突笔记", "您的所有同步冲突均已处理干净。", "坚果云 (Nutstore)", "自定义 (Custom)"
**规则:**
- 采用极简风格翻译，例如 `webdavDisableSyncSuccess`, `webdavDisableSync`, `webdavGoToResolve`, `webdavNoConflicts`, `webdavAllConflictsResolved`, `webdavProviderNutstore`, `webdavProviderCustom`。

## 2024-05-24 - [提取 WebDAV 服务商配置表单硬编码]
**发现:** WebDAV 同步配置页面存在硬编码的表单提示（如：服务商配置、未填写必填项的错误提示）。
**规则:** 将表单相关的标题及校验失败文案统一抽取到 `.arb` 文件中，英文翻译采用清晰直接（"Please enter..."）且符合极简主义要求的设计。
## 2026-07-13 - [提取 SlashCommandsMenu 硬编码中文字符串]
**发现:** 在 `lib/widgets/ai/slash_commands_menu.dart` 中发现了硬编码的中文提示语：`'可用命令'` 和 `'输入 / 查看命令'`
**规则:**
- 采用极简风格进行国际化翻译，分别新增 `availableCommands` 和 `typeSlashToSeeCommands` 到所有 `app_*.arb` 语言包中。
