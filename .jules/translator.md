## 2024-05-30 - 统一媒体导入弹窗 (Unified Media Import Dialog)

**发现:** `lib/widgets/unified_media_import_dialog.dart` 中存在使用字符串插值拼接的硬编码中文操作名称，如 `'选择${_getMediaTypeName(widget.mediaType)}文件'`、`'保存${_getMediaTypeName(widget.mediaType)}文件'` 等，这会导致翻译不自然，并且在不同语言环境（如英语）中显示为中英文混合（如 "选择Image文件"）。

**规则:**
1. 对于带参数的动态文本，必须使用带占位符的 ARB 结构（例如 `{mediaType}`）。
2. 在 `app_zh.arb` 和 `app_en.arb` 中统一添加格式化的带参数翻译。
3. 替换代码中的插值拼接为完整的 i18n 函数调用，如 `l10n.unifiedMediaImportSelectMediaFile(_getMediaTypeName(widget.mediaType))`，确保整体句式结构能够自然适应不同语言的语序。
