import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

/// 许可证页面
/// 显示应用使用的第三方资源许可信息
class LicensePage extends StatelessWidget {
  const LicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('许可证信息')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionCard(
            context,
            title: '开源库与鸣谢',
            icon: Icons.code_outlined,
            content: _buildAcknowledgementsSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            title: 'Lottie 动画许可',
            icon: Icons.animation_outlined,
            content: _buildLottieSection(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildLottieSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '应用使用了来自 LottieFiles 的动画资源：',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        _buildLottieAttribution(
          context: context,
          title: '搜索加载动画',
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/search-loading',
        ),
        _buildLottieAttribution(
          context: context,
          title: '天气搜索动画',
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/weather-search',
        ),
        _buildLottieAttribution(
          context: context,
          title: 'AI思考动画',
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/ai-loading',
        ),
        _buildLottieAttribution(
          context: context,
          title: '搜索无结果动画',
          creator: 'LottieFiles',
          url: 'https://lottiefiles.com/animations/not-found',
        ),
        const SizedBox(height: 12),
        const Text(
          '感谢 LottieFiles 提供优质的动画资源。',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildAcknowledgementsSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '本应用基于 Flutter 框架构建，使用并感谢下列开源库与服务：',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        // 列出库并附带许可证与链接（以上游仓库/包管理页面为准）
        _buildAttributionRow(
          context: context,
          title: '框架',
          name: 'Flutter',
          url: 'https://github.com/flutter/flutter',
          description: '许可证：BSD-3（以 Flutter 仓库为准）',
        ),
        _buildAttributionRow(
          context: context,
          title: '状态管理',
          name: 'Provider',
          url: 'https://pub.dev/packages/provider',
          description: '许可证：MIT（以包仓库为准）',
        ),
        _buildAttributionRow(
          context: context,
          title: '动画支持',
          name: 'Lottie (lottie_flutter / lottie)',
          url: 'https://pub.dev/packages/lottie',
          description: '许可证：MIT（以包仓库为准）',
        ),
        _buildAttributionRow(
          context: context,
          title: '本地存储',
          name: 'MMKV (本项目使用 Dart 适配)',
          url: 'https://github.com/Tencent/MMKV',
          description: '许可证：BSD-3（以 upstream 仓库为准），用于高性能键值存储与缓存',
        ),
        _buildAttributionRow(
          context: context,
          title: '数据库',
          name: 'SQLite',
          url: 'https://www.sqlite.org/',
          description: '许可证：Public Domain（请以 SQLite 官方为准），用于笔记存储与查询',
        ),
        const SizedBox(height: 8),
        // 同步功能相关鸣谢
        Text(
          '同步功能集成说明：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        _buildAttributionRow(
          context: context,
          title: '笔记同步',
          name: 'LocalSend（部分代码集成）',
          url: 'https://github.com/localsend/localsend',
          description:
              '同步功能参考并集成了 LocalSend 项目中的部分实现/代码片段。已遵循并保留原始项目的许可证和作者信息，请参见上方链接以获取详细许可证信息。',
        ),
        const SizedBox(height: 12),
        Text(
          '服务与 API 鸣谢：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildAttributionRow(
          context: context,
          title: '天气数据',
          name: 'Open-Meteo',
          url: 'https://open-meteo.com/',
          description: '提供气象与温度数据的免费 API，用于应用内天气功能。',
        ),
        _buildAttributionRow(
          context: context,
          title: '每日一言 API',
          name: 'Hitokoto (v1.hitokoto.cn)',
          url: 'https://hitokoto.cn/',
          description: '提供简短引言/一言数据，用于每日一言与笔记引用功能。',
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => _launchUrl(
            'https://flutter.dev/docs/development/packages-and-plugins/using-packages',
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('查看完整依赖列表'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '感谢所有开源项目与社区贡献者，正是这些工具和服务让本应用成为可能。具体许可证请以各项目仓库或包管理页面为准。',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withAlpha((0.7 * 255).round()),
          ),
        ),
      ],
    );
  }

  Widget _buildAttributionRow({
    required BuildContext context,
    required String title,
    required String name,
    required String url,
    String? description,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title: $name',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchUrl(url),
                  child: Text(
                    url,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLottieAttribution({
    required BuildContext context,
    required String title,
    required String creator,
    required String url,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          const Icon(Icons.animation_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                InkWell(
                  onTap: () => _launchUrl(url),
                  child: Text(
                    '来源: $creator',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // 如果无法启动URL，静默失败或显示错误
      debugPrint('无法打开链接: $url');
    }
  }
}
