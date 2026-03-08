part of '../note_full_editor_page.dart';

/// Color picker dialog and media file processing.
extension NoteEditorColorAndMedia on _NoteFullEditorPageState {
  Future<void> _showCustomColorPicker(BuildContext context) async {
    final Color initialColor = _selectedColorHex != null
        ? Color(
            int.parse(_selectedColorHex!.substring(1), radix: 16) | 0xFF000000,
          )
        : Colors.transparent;

    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // 预设颜色列表 - 更现代的轻柔色调
    final List<Color> presetColors = [
      Colors.transparent, // 透明/无
      const Color(0xFFF9E4E4), // 轻红色
      const Color(0xFFFFF0E1), // 轻橙色
      const Color(0xFFFFFBE5), // 轻黄色
      const Color(0xFFE8F5E9), // 轻绿色
      const Color(0xFFE1F5FE), // 轻蓝色
      const Color(0xFFF3E5F5), // 轻紫色
      const Color(0xFFFCE4EC), // 轻粉色

      const Color(0xFFEF9A9A), // 红色
      const Color(0xFFFFE0B2), // 橙色
      const Color(0xFFFFF9C4), // 黄色
      const Color(0xFFC8E6C9), // 绿色
      const Color(0xFFBBDEFB), // 蓝色
      const Color(0xFFE1BEE7), // 紫色
      const Color(0xFFF8BBD0), // 粉色

      const Color(0xFFEF9A9A), // 深红色
      const Color(0xFFFFCC80), // 深橙色
      const Color(0xFFFFF59D), // 深黄色
      const Color(0xFFA5D6A7), // 深绿色
      const Color(0xFF90CAF9), // 深蓝色
      const Color(0xFFCE93D8), // 深紫色
      const Color(0xFFF48FB1), // 深粉色
    ];

    final Color? result = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).selectCardColor),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预设颜色网格
              Container(
                width: 280,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        AppLocalizations.of(context).presetColors,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.start,
                      children: presetColors.map((color) {
                        String? colorHex;
                        if (color != Colors.transparent) {
                          colorHex =
                              '#${color.toARGB32().toRadixString(16).substring(2)}';
                        }

                        final bool isSelected = color == Colors.transparent
                            ? _selectedColorHex == null
                            : _selectedColorHex == colorHex;

                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop(color);
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(21),
                              border: Border.all(
                                color: isSelected
                                    ? colorScheme.primary
                                    : color == Colors.transparent
                                        ? Colors.grey
                                            .applyOpacity(0.5) // MODIFIED
                                        : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.applyOpacity(
                                    0.05,
                                  ), // MODIFIED
                                  spreadRadius: 1,
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Center(
                              child: isSelected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: color == Colors.transparent ||
                                              color.computeLuminance() > 0.7
                                          ? colorScheme.primary
                                          : Colors.white,
                                      size: 24,
                                    )
                                  : color == Colors.transparent
                                      ? const Icon(
                                          Icons.block,
                                          color: Colors.grey,
                                          size: 18,
                                        )
                                      : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 高级颜色选择按钮
              OutlinedButton.icon(
                icon: const Icon(Icons.color_lens),
                label: Text(AppLocalizations.of(context).customColor),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context); // 关闭当前对话框

                  // 打开高级颜色选择器
                  final Color? advancedColor = await showDialog<Color>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(AppLocalizations.of(context).customColor),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          color: initialColor != Colors.transparent
                              ? initialColor
                              : const Color(0xFFE1F5FE), // 默认蓝色
                          onColorChanged: (color) {},
                          width: 40,
                          height: 40,
                          spacing: 10,
                          runSpacing: 10,
                          borderRadius: 20,
                          wheelDiameter: 200,
                          enableShadesSelection: true,
                          pickersEnabled: const {
                            ColorPickerType.primary: true,
                            ColorPickerType.accent: false,
                            ColorPickerType.wheel: true,
                          },
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(AppLocalizations.of(context).cancel),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(initialColor),
                          child: Text(AppLocalizations.of(context).select),
                        ),
                      ],
                    ),
                  );

                  if (advancedColor != null && mounted) {
                    // 优化：合并所有状态更新为单次 setState 调用
                    setState(() {
                      _selectedColorHex = advancedColor == Colors.transparent
                          ? null
                          : '#${advancedColor.toARGB32().toRadixString(16).substring(2)}';
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    if (result != null) {
      // 优化：合并所有状态更新为单次 setState 调用
      setState(() {
        _selectedColorHex = result == Colors.transparent
            ? null
            : '#${result.toARGB32().toRadixString(16).substring(2)}';
      });
    }
  }
  Future<void> _processTemporaryMediaFiles({
    void Function(double progress, String? status)? onProgress,
    void Function(String permanentPath)? onFileMoved,
  }) async {
    try {
      logDebug('开始处理临时媒体文件...');

      // 获取当前文档的Delta内容
      final deltaData = _controller.document.toDelta().toJson();
      // 修复：使用深拷贝确保备份数据完全独立，避免嵌套对象的意外修改
      final originalDeltaData = _deepCopy(deltaData) as List;
      bool hasChanges = false;
      final processedFiles = <String, String>{}; // 记录已处理的文件映射

      // 预扫描：统计需要处理的临时媒体文件
      final mediaEntries = <Map<String, dynamic>>[];
      for (final op in deltaData) {
        if (op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is Map) {
            if (insert.containsKey('image')) {
              mediaEntries.add({'ref': insert, 'key': 'image', 'type': '图片'});
            }
            if (insert.containsKey('video')) {
              mediaEntries.add({'ref': insert, 'key': 'video', 'type': '视频'});
            }
            if (insert.containsKey('custom')) {
              final custom = insert['custom'];
              if (custom is Map && custom.containsKey('audio')) {
                mediaEntries.add({'ref': custom, 'key': 'audio', 'type': '音频'});
              }
            }
          }
        }
      }
      final total = mediaEntries.length;
      var done = 0;
      if (total == 0) {
        onProgress?.call(1.0, '无需处理媒体文件');
      } else {
        onProgress?.call(0.0, '发现 $total 个媒体文件');
      }

      for (final entry in mediaEntries) {
        final ref = entry['ref'] as Map;
        final key = entry['key'] as String;
        final typeLabel = entry['type'] as String;
        final pathVal = ref[key] as String?;
        if (pathVal != null &&
            await TemporaryMediaService.isTemporaryFile(pathVal)) {
          final newPath = await _moveMediaFileSafely(
            pathVal,
            processedFiles,
            onFileProgress: (fileProg) {
              if (total > 0) {
                final overall = (done + fileProg) / total;
                onProgress?.call(overall, '复制$typeLabel ${done + 1}/$total');
              }
            },
          );
          if (newPath != null) {
            ref[key] = newPath;
            hasChanges = true;
            onFileMoved?.call(newPath);
          }
        }
        done++;
        if (total > 0) {
          onProgress?.call(done / total, '已处理 $done / $total');
        }
      }

      // 遍历Delta内容，查找临时媒体文件
      for (final op in deltaData) {
        if (op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is Map) {
            // 处理图片
            if (insert.containsKey('image')) {
              final imagePath = insert['image'] as String?;
              if (imagePath != null &&
                  await TemporaryMediaService.isTemporaryFile(imagePath)) {
                final permanentPath = await _moveMediaFileSafely(
                  imagePath,
                  processedFiles,
                );
                if (permanentPath != null) {
                  insert['image'] = permanentPath;
                  hasChanges = true;
                  logDebug('临时图片已移动: $imagePath -> $permanentPath');
                  onFileMoved?.call(permanentPath);
                }
              }
            }

            // 处理视频
            if (insert.containsKey('video')) {
              final videoPath = insert['video'] as String?;
              if (videoPath != null &&
                  await TemporaryMediaService.isTemporaryFile(videoPath)) {
                final permanentPath = await _moveMediaFileSafely(
                  videoPath,
                  processedFiles,
                );
                if (permanentPath != null) {
                  insert['video'] = permanentPath;
                  hasChanges = true;
                  logDebug('临时视频已移动: $videoPath -> $permanentPath');
                  onFileMoved?.call(permanentPath);
                }
              }
            }

            // 处理自定义嵌入（如音频）
            if (insert.containsKey('custom')) {
              final custom = insert['custom'];
              if (custom is Map && custom.containsKey('audio')) {
                final audioPath = custom['audio'] as String?;
                if (audioPath != null &&
                    await TemporaryMediaService.isTemporaryFile(audioPath)) {
                  final permanentPath = await _moveMediaFileSafely(
                    audioPath,
                    processedFiles,
                  );
                  if (permanentPath != null) {
                    custom['audio'] = permanentPath;
                    hasChanges = true;
                    logDebug('临时音频已移动: $audioPath -> $permanentPath');
                    onFileMoved?.call(permanentPath);
                  }
                }
              }
            }
          }
        }
      }

      // 只有在有变更时才更新编辑器内容
      if (hasChanges) {
        try {
          final newDocument = quill.Document.fromJson(deltaData);
          _controller.document = newDocument;
          logDebug('临时媒体文件处理完成，共处理 ${processedFiles.length} 个文件');
        } catch (e) {
          logDebug('更新编辑器内容失败，回滚到原始状态: $e');
          // 回滚到原始状态
          final rollbackDocument = quill.Document.fromJson(originalDeltaData);
          _controller.document = rollbackDocument;
          rethrow;
        }
      } else {
        logDebug('没有临时媒体文件需要处理');
      }
    } catch (e) {
      logDebug('处理临时媒体文件失败: $e');
      rethrow;
    }
  }
  Future<String?> _moveMediaFileSafely(
    String sourcePath,
    Map<String, String> processedFiles, {
    Function(double progress)? onFileProgress,
  }) async {
    try {
      // 检查是否已经处理过这个文件
      if (processedFiles.containsKey(sourcePath)) {
        return processedFiles[sourcePath];
      }

      final permanentPath = await TemporaryMediaService.moveToPermament(
        sourcePath,
        onProgress: onFileProgress,
        deleteSource: false,
      );
      if (permanentPath != null) {
        processedFiles[sourcePath] = permanentPath;
      }
      return permanentPath;
    } catch (e) {
      logDebug('移动媒体文件失败: $sourcePath, 错误: $e');
      return null;
    }
  }
  Future<void> _cleanupTemporaryMedia() async {
    try {
      await TemporaryMediaService.cleanupExpiredTemporaryFiles();
      logDebug('临时媒体文件清理完成');
    } catch (e) {
      logDebug('清理临时媒体文件失败: $e');
    }
  }
  Future<void> _cleanupSessionImportedMediaIfUnsaved() async {
    try {
      if (_didSaveSuccessfully || _sessionImportedMedia.isEmpty) return;

      // 获取草稿引用的媒体文件，避免误删
      final draftMediaPaths = await DraftService().getAllMediaPathsInDrafts();

      await Future.wait(_sessionImportedMedia.map((p) async {
        try {
          // 如果被草稿引用，跳过删除
          if (draftMediaPaths.contains(p)) {
            logDebug('文件被草稿引用，跳过会话级清理: $p');
            return;
          }

          final refCount = await MediaReferenceService.getReferenceCount(p);
          if (refCount <= 0) {
            final deleted = await MediaFileService.deleteMediaFile(p);
            if (deleted) {
              logDebug('未保存退出，已删除未引用媒体文件: $p');
            }
          }
        } catch (e) {
          logDebug('清理会话媒体失败: $p, 错误: $e');
        }
      }));
    } catch (e) {
      logDebug('执行会话级媒体清理出错: $e');
    }
  }
}
