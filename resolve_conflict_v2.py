import re

file_path = 'lib/widgets/add_note_dialog.dart'

with open(file_path, 'r') as f:
    content = f.read()

# Define the resolved code block
# This covers from onPressed to the end of the child widget
resolved_code = r'''                  // 保存时保持按钮样式但不响应点击，避免视觉闪烁
                  onPressed: (_isSaving || _isLoadingFullQuote)
                      ? (_isSaving ? () {} : null)
                      : () async {
                    if (_contentController.text.isNotEmpty) {
                      setState(() {
                        _isSaving = true;
                      });
                      try {
                        // 获取当前时间段
                        final String currentDayPeriodKey =
                            TimeUtils.getCurrentDayPeriodKey(); // 使用 Key

                        // 创建或更新笔记
                        // 使用实时获取的位置（新建）或原始位置（编辑）
                        final isEditing = widget.initialQuote != null;
                        final baseQuote =
                            _fullInitialQuote ?? widget.initialQuote;

                        final Quote quote = Quote(
                          id: widget.initialQuote?.id ?? const Uuid().v4(),
                          content: _contentController.text,
                          date: widget.initialQuote?.date ??
                              DateTime.now().toIso8601String(),
                          aiAnalysis: _aiSummary,
                          source: _formatSource(
                            _authorController.text,
                            _workController.text,
                          ),
                          sourceAuthor: _authorController.text,
                          sourceWork: _workController.text,
                          tagIds: _selectedTagIds,
                          sentiment: baseQuote?.sentiment,
                          keywords: baseQuote?.keywords,
                          summary: baseQuote?.summary,
                          categoryId: _selectedCategory?.id ??
                              widget.initialQuote?.categoryId,
                          colorHex: _selectedColorHex,
                          location: _includeLocation
                              ? (isEditing
                                  ? _originalLocation
                                  : _newLocation ??
                                      _cachedLocationService
                                          ?.getFormattedLocation())
                              : null,
                          latitude: _includeLocation
                              ? (isEditing ? _originalLatitude : _newLatitude)
                              : null,
                          longitude: _includeLocation
                              ? (isEditing ? _originalLongitude : _newLongitude)
                              : null,
                          weather: _includeWeather
                              ? (isEditing
                                  ? _originalWeather
                                  : _cachedWeatherService?.currentWeather)
                              : null,
                          temperature: _includeWeather
                              ? (isEditing
                                  ? _originalTemperature
                                  : _cachedWeatherService?.temperature)
                              : null,
                          dayPeriod: widget.initialQuote?.dayPeriod ??
                              currentDayPeriodKey, // 保存 Key
                          editSource: widget.initialQuote?.editSource, // 保证兼容
                          deltaContent: widget.initialQuote?.deltaContent, // 保证兼容
                        );

                        final db = Provider.of<DatabaseService>(
                          context,
                          listen: false,
                        );

                        if (widget.initialQuote != null) {
                          // 更新已有笔记
                          await db.updateQuote(quote);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(context).noteUpdated,
                              ),
                              duration: AppConstants.snackBarDurationImportant,
                            ),
                          );
                        } else {
                          // 添加新笔记
                          await db.addQuote(quote);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(context).noteSaved,
                              ),
                              duration: AppConstants.snackBarDurationImportant,
                            ),
                          );
                        }

                        // 调用保存回调
                        if (widget.onSave != null) {
                          widget.onSave!(quote);
                        }

                        // 在保存后请求AI推荐标签（仅新建笔记时）
                        if (!isEditing) {
                          await _showAIRecommendedTags(quote.content);
                        }

                        // 关闭对话框
                        if (this.context.mounted) {
                          Navigator.of(context).pop();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(
                                  context,
                                ).saveFailedWithError(e.toString()),
                              ),
                              duration: AppConstants.snackBarDurationError,
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } finally {
                         if (mounted) {
                           setState(() {
                             _isSaving = false;
                           });
                         }
                      }
                    }
                  },
                  child: (_isSaving || _isLoadingFullQuote)
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                                _isSaving ? theme.colorScheme.onPrimary : null,
                          ),
                        )
                      : Text(
                          widget.initialQuote != null
                              ? AppLocalizations.of(context).edit
                              : AppLocalizations.of(context).save,
                        ),'''

# Find the start of the first conflict marker
start_marker = "<<<<<<< ours"
end_marker = ">>>>>>> theirs"

start_idx = content.find(start_marker)
if start_idx == -1:
    # Try alternate markers if 'ours' not found
    start_marker = "<<<<<<< Updated upstream"
    end_marker = ">>>>>>> Stashed changes"
    start_idx = content.find(start_marker)

if start_idx != -1:
    # Find the END of the LAST conflict marker in this block
    # Since there are two adjacent blocks, we want the end of the second block.
    # We can just look for the last occurrence of end_marker in the file?
    # No, that might be too aggressive if there are other conflicts (unlikely but possible).

    # We will search for the end_marker starting from start_idx
    # Since we saw TWO blocks, we need to skip the first end_marker and find the second one.

    first_end_idx = content.find(end_marker, start_idx)
    second_start_idx = content.find(start_marker, first_end_idx + len(end_marker))

    # Check if the second start is immediately after (ignoring whitespace)
    if second_start_idx != -1:
        # Assuming the second block is the 'child' block
        final_end_idx = content.find(end_marker, second_start_idx) + len(end_marker)

        # Replace the whole range from start_idx to final_end_idx
        new_content = content[:start_idx] + resolved_code + content[final_end_idx:]

        with open(file_path, 'w') as f:
            f.write(new_content)
        print("Successfully resolved both conflict blocks.")
    else:
        # Maybe only one block?
        final_end_idx = first_end_idx + len(end_marker)
        new_content = content[:start_idx] + resolved_code + content[final_end_idx:]
        with open(file_path, 'w') as f:
            f.write(new_content)
        print("Successfully resolved one conflict block.")

else:
    print("Could not find conflict markers.")
