import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/constants/app_constants.dart';

class FeedbackContactPage extends StatelessWidget {
  const FeedbackContactPage({super.key});

  static const String _feedbackUrl =
      'https://github.com/Shangjin-Xiao/ThoughtEcho/issues/new/choose';
  static const String _projectUrl =
      'https://github.com/Shangjin-Xiao/ThoughtEcho';
  static const String _discussionUrl =
      'https://github.com/Shangjin-Xiao/ThoughtEcho/discussions';
  static const String _emailUrl = 'mailto:shangjinyun@proton.me';

  Future<void> _launchUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cannotOpenLink(url)),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedbackAndContact),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.feedbackAndContactDesc,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.bug_report_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(l10n.feedbackGithubTitle),
                  subtitle: Text(l10n.feedbackGithubDesc),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(context, _feedbackUrl),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.forum_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(l10n.feedbackDiscussionTitle),
                  subtitle: Text(l10n.feedbackDiscussionDesc),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(context, _discussionUrl),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.code_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(l10n.feedbackGithubRepoTitle),
                  subtitle: Text(l10n.feedbackGithubRepoDesc),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(context, _projectUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.contactDeveloperSectionTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.email_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(l10n.feedbackEmailTitle),
                  subtitle: Text(l10n.feedbackEmailDesc),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(context, _emailUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
