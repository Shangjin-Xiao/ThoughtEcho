import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

/// User Guide Page - displays the user manual markdown content
class UserGuidePage extends StatefulWidget {
  const UserGuidePage({super.key});

  @override
  State<UserGuidePage> createState() => _UserGuidePageState();
}

class _UserGuidePageState extends State<UserGuidePage> {
  late Future<String> _markdownFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _markdownFuture = _loadMarkdown();
  }

  Future<String> _loadMarkdown() async {
    final locale = Localizations.localeOf(context);
    final isZh = locale.languageCode == 'zh';
    final assetPath = isZh
        ? 'assets/docs/user_manual_zh.md'
        : 'assets/docs/user_manual_en.md';

    try {
      return await rootBundle.loadString(assetPath);
    } catch (e) {
      // Fallback to Chinese if English not found
      try {
        return await rootBundle.loadString('assets/docs/user_manual_zh.md');
      } catch (e2) {
        rethrow;
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.userGuide),
        centerTitle: true,
      ),
      body: FutureBuilder<String>(
        future: _markdownFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.loadFailed(snapshot.error.toString()),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                ),
              ),
            );
          }

          final markdownData = snapshot.data ?? '';

          return Markdown(
            data: markdownData,
            selectable: true,
            padding: const EdgeInsets.all(16.0),
            onTapLink: (text, href, title) {
              if (href != null) {
                _launchUrl(href);
              }
            },
            styleSheet: MarkdownStyleSheet(
              h1: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              h2: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
              h3: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              p: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: colorScheme.onSurface,
              ),
              listBullet: TextStyle(
                color: colorScheme.primary,
              ),
              tableHead: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              tableBody: TextStyle(
                color: colorScheme.onSurface,
              ),
              tableBorder: TableBorder.all(
                color: colorScheme.outlineVariant,
                width: 1,
              ),
              blockquoteDecoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: colorScheme.primary,
                    width: 4,
                  ),
                ),
              ),
              codeblockDecoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              code: TextStyle(
                backgroundColor: colorScheme.surfaceContainerHighest,
                fontFamily: 'monospace',
                fontSize: 14,
              ),
            ),
          );
        },
      ),
    );
  }
}
