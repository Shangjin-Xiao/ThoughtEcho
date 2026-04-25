part of '../settings_page.dart';

extension _SettingsPageBuilders on SettingsPageState {
  // 构建语言设置项
  Widget _buildLanguageItem(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final currentLocale = settingsService.localeCode;
    final l10n = AppLocalizations.of(context);

    String getLanguageName(String? code) {
      switch (code) {
        case 'zh':
          return l10n.languageChinese;
        case 'en':
          return l10n.languageEnglish;
        case 'ja':
          return l10n.languageJapanese;
        case 'ko':
          return l10n.languageKorean;
        case 'es':
          return l10n.languageSpanish;
        case 'fr':
          return l10n.languageFrench;
        case 'de':
          return l10n.languageGerman;
        default:
          return l10n.languageFollowSystem;
      }
    }

    return ListTile(
      title: Text(l10n.languageSettings),
      subtitle: Text(getLanguageName(currentLocale)),
      leading: const Icon(Icons.translate),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.selectLanguage),
            content: StatefulBuilder(
              builder: (context, setState) {
                return RadioGroup<String?>(
                  groupValue: currentLocale,
                  onChanged: (value) async {
                    await settingsService.setLocale(value);
                    // 同步更新位置服务的语言设置
                    locationService.currentLocaleCode = value;
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String?>(
                        title: Text(l10n.languageFollowSystem),
                        value: null,
                      ),
                      RadioListTile<String?>(
                        title: Text(l10n.languageChinese),
                        value: 'zh',
                      ),
                      RadioListTile<String?>(
                        title: const Text('English'),
                        value: 'en',
                      ),
                      RadioListTile<String?>(
                        title: const Text('日本語'),
                        value: 'ja',
                      ),
                      RadioListTile<String?>(
                        title: const Text('한국어'),
                        value: 'ko',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Español'),
                        value: 'es',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Français'),
                        value: 'fr',
                      ),
                      RadioListTile<String?>(
                        title: const Text('Deutsch'),
                        value: 'de',
                      ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        );
      },
    );
  }

  // 构建默认启动页面设置项
  Widget _buildDefaultStartPageItem(BuildContext context) {
    // 从 SettingsService 获取设置
    final settingsService = Provider.of<SettingsService>(context);
    final currentValue = settingsService.appSettings.defaultStartPage;
    final l10n = AppLocalizations.of(context);

    return ListTile(
      key: _startupPageGuideKey, // 功能引导 key
      title: Text(l10n.settingsDefaultStartPage),
      subtitle: Text(
        currentValue == 0
            ? l10n.settingsStartPageHome
            : l10n.settingsStartPageNotes,
      ),
      leading: const Icon(Icons.home_outlined),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.settingsSelectStartPage),
            content: StatefulBuilder(
              builder: (context, setState) {
                return RadioGroup<int>(
                  groupValue: currentValue,
                  onChanged: (value) {
                    if (value != null) {
                      settingsService.updateAppSettings(
                        settingsService.appSettings.copyWith(
                          defaultStartPage: value,
                        ),
                      );
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<int>(
                        title: Text(l10n.settingsStartPageHome),
                        value: 0,
                      ),
                      RadioListTile<int>(
                        title: Text(l10n.settingsStartPageNotes),
                        value: 1,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 显示原生年度报告
  // ignore: unused_element
  Future<void> _showNativeAnnualReport() async {
    try {
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final quotes = await databaseService.getUserQuotes();
      final currentYear = DateTime.now().year;

      final thisYearQuotes = quotes.where((quote) {
        final quoteDate = DateTime.parse(quote.date);
        return quoteDate.year == currentYear;
      }).toList();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                // ignore: deprecated_member_use_from_same_package
                AnnualReportPage(year: currentYear, quotes: thisYearQuotes),
          ),
        );
      }
    } catch (e) {
      AppLogger.e('显示原生年度报告失败', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.generateReportFailed),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 显示AI年度报告
  // ignore: unused_element
  Future<void> _showAIAnnualReport() async {
    try {
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final quotes = await databaseService.getUserQuotes();
      final currentYear = DateTime.now().year;

      final thisYearQuotes = quotes.where((quote) {
        final quoteDate = DateTime.parse(quote.date);
        return quoteDate.year == currentYear;
      }).toList();

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        // 显示加载对话框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text(l10n.generatingAiReport),
              ],
            ),
          ),
        );

        try {
          final aiService = Provider.of<AIService>(context, listen: false);

          // 准备数据摘要
          final totalNotes = thisYearQuotes.length;
          final totalWords = thisYearQuotes.fold<int>(
            0,
            (sum, quote) => sum + quote.content.length,
          );
          final averageWordsPerNote =
              totalNotes > 0 ? (totalWords / totalNotes).round() : 0;

          // 获取标签统计
          final Map<String, int> tagCounts = {};
          for (final quote in thisYearQuotes) {
            for (final tagId in quote.tagIds) {
              tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
            }
          }

          // 获取积极的笔记内容示例
          final positiveKeywords = [
            '成长',
            '学习',
            '进步',
            '成功',
            '快乐',
            '感谢',
            '收获',
            '突破',
            '希望',
          ];
          final positiveQuotes = thisYearQuotes
              .where(
                (quote) => positiveKeywords.any(
                  (keyword) => quote.content.contains(keyword),
                ),
              )
              .take(5)
              .map((quote) => quote.content)
              .join('\n');

          // 获取月度分布数据
          final Map<int, int> monthlyData = {};
          for (int i = 1; i <= 12; i++) {
            monthlyData[i] = 0;
          }
          for (final quote in thisYearQuotes) {
            final quoteDate = DateTime.parse(quote.date);
            monthlyData[quoteDate.month] =
                (monthlyData[quoteDate.month] ?? 0) + 1;
          }

          // 获取标签信息
          final allCategories = await databaseService.getCategories();
          final tagNames = <String>[];
          for (final tagId in tagCounts.keys.take(10)) {
            final category = allCategories.firstWhere(
              (c) => c.id == tagId,
              orElse: () => NoteCategory(id: tagId, name: '未知标签'),
            );
            tagNames.add(category.name);
          }

          // 获取时间段分布
          final Map<String, int> timePeriods = {
            '早晨': 0,
            '上午': 0,
            '下午': 0,
            '傍晚': 0,
            '夜晚': 0,
          };

          for (final quote in thisYearQuotes) {
            final quoteDate = DateTime.parse(quote.date);
            final hour = quoteDate.hour;
            if (hour >= 5 && hour < 9) {
              timePeriods['早晨'] = (timePeriods['早晨'] ?? 0) + 1;
            } else if (hour >= 9 && hour < 12) {
              timePeriods['上午'] = (timePeriods['上午'] ?? 0) + 1;
            } else if (hour >= 12 && hour < 18) {
              timePeriods['下午'] = (timePeriods['下午'] ?? 0) + 1;
            } else if (hour >= 18 && hour < 22) {
              timePeriods['傍晚'] = (timePeriods['傍晚'] ?? 0) + 1;
            } else {
              timePeriods['夜晚'] = (timePeriods['夜晚'] ?? 0) + 1;
            }
          }

          final peakTime = timePeriods.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;

          // 修复：活跃记录天数应按"年月日"去重，而非仅按"日号"
          final int uniqueActiveDays = thisYearQuotes
              .map((q) {
                final d = DateTime.parse(q.date);
                return DateTime(d.year, d.month, d.day);
              })
              .toSet()
              .length;

          final prompt = '''基于以下用户笔记数据，生成一份完整的HTML年度报告。

用户数据统计：
- 年份：$currentYear
- 总笔记数：$totalNotes 篇
- 总字数：$totalWords 字
- 平均每篇字数：$averageWordsPerNote 字
- 活跃记录天数：$uniqueActiveDays 天
- 使用标签数：${tagCounts.length} 个

月度分布数据：
${monthlyData.entries.map((e) => '${e.key}月: ${e.value}篇').join('\n')}

主要标签（按使用频率）：
${tagNames.take(10).join(', ')}

最活跃记录时间：$peakTime

部分积极内容示例：
${positiveQuotes.isNotEmpty ? positiveQuotes : '用户的记录充满了思考和成长的足迹。'}

请生成一份完整的HTML年度报告，要求：
1. 必须返回完整的HTML代码，从<!DOCTYPE html>开始到</html>结束
2. 不要返回JSON或其他格式，只返回HTML
3. 使用现代化的移动端友好设计
4. 包含所有真实的统计数据
5. 精选积极正面的笔记内容作为回顾
6. 生成鼓励性的洞察和建议
7. 保持温暖积极的语调
8. 确保HTML可以在浏览器中正常显示

请直接返回HTML代码，不需要任何解释。''';

          AppLogger.i('开始生成AI年度报告，数据统计：总笔记$totalNotes篇，总字数$totalWords字');

          final result = await aiService.generateAnnualReportHTML(prompt);

          AppLogger.i('AI年度报告生成完成，内容长度：${result.length}字符');

          if (!mounted) return;
          Navigator.pop(context); // 关闭加载对话框

          if (mounted && result.isNotEmpty) {
            // 检查返回内容的格式
            final isHtml =
                result.trim().toLowerCase().startsWith('<!doctype') ||
                    result.trim().toLowerCase().startsWith('<html');
            final isJson =
                result.trim().startsWith('{') || result.trim().startsWith('[');

            AppLogger.i('AI返回内容格式检查：isHtml=$isHtml, isJson=$isJson');

            if (isJson) {
              AppLogger.w('AI返回了JSON格式而非HTML，可能是模型理解错误');
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AIAnnualReportWebView(
                  htmlContent: result,
                  year: currentYear,
                ),
              ),
            );
          } else {
            AppLogger.w('AI返回了空内容');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).aiReturnedEmptyContent,
                  ),
                  duration: AppConstants.snackBarDurationError,
                ),
              );
            }
          }
        } catch (e) {
          AppLogger.e('生成AI年度报告失败', error: e);
          if (mounted) {
            Navigator.pop(context); // 关闭加载对话框

            String errorMessage = '生成AI年度报告失败';
            if (e.toString().contains('API Key')) {
              errorMessage = '请先在AI设置中配置有效的API Key';
            } else if (e.toString().contains('network') ||
                e.toString().contains('连接')) {
              errorMessage = '网络连接异常，请检查网络后重试';
            } else if (e.toString().contains('quota') ||
                e.toString().contains('limit')) {
              errorMessage = 'AI服务配额不足，请稍后重试';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      AppLogger.e('显示AI年度报告失败', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.getDataFailed),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 测试AI年度报告功能
  // ignore: unused_element
  Future<void> _testAIAnnualReport() async {
    final l10n = AppLocalizations.of(context);
    try {
      AppLogger.i('开始测试AI年度报告功能');

      // 显示测试对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(l10n.testingAIReport),
            ],
          ),
        ),
      );

      try {
        final aiService = Provider.of<AIService>(context, listen: false);

        // 使用简化的测试数据
        const testPrompt = '''基于以下用户笔记数据，生成一份完整的HTML年度报告。

用户数据统计：
- 年份：2024
- 总笔记数：100 篇
- 总字数：5000 字
- 平均每篇字数：50 字
- 活跃记录天数：200 天
- 使用标签数：10 个

月度分布数据：
1月: 8篇
2月: 12篇
3月: 15篇
4月: 10篇
5月: 9篇
6月: 11篇
7月: 13篇
8月: 7篇
9月: 6篇
10月: 4篇
11月: 3篇
12月: 2篇

主要标签（按使用频率）：
个人成长, 工作思考, 读书笔记, 生活感悟, 技术学习

最活跃记录时间：晚上

部分积极内容示例：
今天学会了新的技术，感觉很有成就感。
和朋友聊天收获很多，人际关系让我成长了不少。
读了一本好书，对人生有了新的理解。

请生成一份完整的HTML年度报告，要求：
1. 必须返回完整的HTML代码，从<!DOCTYPE html>开始到</html>结束
2. 不要返回JSON或其他格式，只返回HTML
3. 使用现代化的移动端友好设计
4. 包含所有真实的统计数据
5. 精选积极正面的笔记内容作为回顾
6. 生成鼓励性的洞察和建议
7. 保持温暖积极的语调
8. 确保HTML可以在浏览器中正常显示

请直接返回HTML代码，不需要任何解释。''';

        AppLogger.i('发送测试提示词给AI');

        final result = await aiService.generateAnnualReportHTML(testPrompt);

        AppLogger.i('AI测试报告生成完成，内容长度：${result.length}字符');

        if (!mounted) return;
        Navigator.pop(context); // 关闭加载对话框

        if (mounted && result.isNotEmpty) {
          // 详细检查返回内容
          final trimmed = result.trim();
          final isHtml = trimmed.toLowerCase().startsWith('<!doctype') ||
              trimmed.toLowerCase().startsWith('<html');
          final isJson = trimmed.startsWith('{') || trimmed.startsWith('[');
          final containsHtmlTags = trimmed.contains('<html') ||
              trimmed.contains('<body') ||
              trimmed.contains('<div');

          AppLogger.i('''
测试结果分析：
- 内容长度：${result.length}字符
- 是HTML格式：$isHtml
- 是JSON格式：$isJson
- 包含HTML标签：$containsHtmlTags
- 前100字符：${trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed}
''');

          // 显示结果对话框
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.testResult),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.contentLengthLabel(result.length)),
                  Text(l10n.htmlFormatLabel(isHtml ? '✅' : '❌')),
                  Text(l10n.jsonFormatLabel(isJson ? '⚠️' : '✅')),
                  Text(
                    l10n.containsHtmlTagsLabel(containsHtmlTags ? '✅' : '❌'),
                  ),
                  const SizedBox(height: 10),
                  Text(l10n.first100CharsLabel),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      trimmed.length > 100
                          ? '${trimmed.substring(0, 100)}...'
                          : trimmed,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.close),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AIAnnualReportWebView(
                          htmlContent: result,
                          year: 2024,
                        ),
                      ),
                    );
                  },
                  child: Text(l10n.viewReport),
                ),
              ],
            ),
          );
        } else {
          AppLogger.w('AI返回了空内容');
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.testFailedEmptyContent),
                duration: AppConstants.snackBarDurationError,
              ),
            );
          }
        }
      } catch (e) {
        AppLogger.e('测试AI年度报告失败', error: e);
        if (mounted) {
          Navigator.pop(context); // 关闭加载对话框

          String errorMessage = l10n.testFailed(e.toString());
          if (e.toString().contains('API Key')) {
            errorMessage = l10n.testFailedApiKey;
          } else if (e.toString().contains('network') ||
              e.toString().contains('连接')) {
            errorMessage = l10n.testFailedNetwork;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.e('测试AI年度报告初始化失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.testInitFailed),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // --- 一周年庆典横幅 ---
  Widget _buildAnniversaryBanner(BuildContext context) {
    final now = DateTime.now();
    final settingsService = context.read<SettingsService>();
    final shouldShow = AnniversaryDisplayUtils.shouldShowSettingsBanner(
      now: now,
      developerMode: settingsService.appSettings.developerMode,
    );
    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFF8FAFC), const Color(0xFFEEF2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showAnniversaryAnimationInSettings(context),
          child: Stack(
            children: [
              // 背景装饰 - 柔和的光晕
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFF818CF8,
                        ).withValues(alpha: isDark ? 0.2 : 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: -40,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFF60A5FA,
                        ).withValues(alpha: isDark ? 0.15 : 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 主内容区
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // 左侧：精致的笔记本图标
                    const AnniversaryNotebookIcon(),
                    const SizedBox(width: 20),
                    // 右侧：文本和指示器
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.anniversaryBannerTitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: isDark
                                  ? const Color(0xFFF8FAFC)
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formatAnniversaryBannerSubtitleForTile(
                              l10n.anniversaryBannerSubtitle,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF475569),
                              height: 1.4,
                            ),
                            softWrap: true,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                l10n.anniversaryBannerTap,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF818CF8)
                                      : const Color(0xFF4F46E5),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: isDark
                                    ? const Color(0xFF818CF8)
                                    : const Color(0xFF4F46E5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
