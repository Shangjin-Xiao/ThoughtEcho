import re

file_path = 'lib/widgets/add_note_dialog.dart'

with open(file_path, 'r') as f:
    content = f.read()

# Define the resolved code block
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

# Regex to match the conflict block
# It starts with <<<<<<< Updated upstream and ends with the closing of the conflict block
# The conflict block in the file looks like:
# <<<<<<< Updated upstream
# ...
# =======
# ...
# >>>>>>> Stashed changes

pattern = re.compile(r'<<<<<<< Updated upstream.*?>>>>>>> Stashed changes', re.DOTALL)

if pattern.search(content):
    new_content = pattern.sub(resolved_code, content)
    with open(file_path, 'w') as f:
        f.write(new_content)
    print("Successfully resolved conflict.")
else:
    print("Could not find conflict markers.")
