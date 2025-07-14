import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
            title: 'Lottie 动画许可',
            icon: Icons.animation_outlined,
            content: _buildLottieSection(context),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context,
            title: '开源库许可',
            icon: Icons.code_outlined,
            content: _buildOpenSourceSection(context),
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

  Widget _buildOpenSourceSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '本应用基于 Flutter 框架构建，使用了以下开源库：',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        const Text(
          '• Flutter - Google\n'
          '• Provider - Remi Rousselet\n'
          '• Lottie - Airbnb\n'
          '• 以及其他优秀的开源项目',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => _launchUrl(
            'https://flutter.dev/docs/development/packages-and-plugins/using-packages',
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('查看完整依赖列表'),
        ),
      ],
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
