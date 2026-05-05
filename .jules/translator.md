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
