import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AIWorkflowNoticeCard extends StatelessWidget {
  const AIWorkflowNoticeCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(message, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AIWorkflowMarkdownCard extends StatelessWidget {
  const AIWorkflowMarkdownCard({
    super.key,
    required this.title,
    required this.content,
    this.icon = Icons.description_outlined,
  });

  final String title;
  final String content;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
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
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MarkdownBody(data: content, selectable: true),
          ],
        ),
      ),
    );
  }
}

class AISourceAnalysisResultCard extends StatelessWidget {
  const AISourceAnalysisResultCard({
    super.key,
    required this.title,
    required this.author,
    required this.work,
    required this.confidence,
    required this.explanation,
    required this.authorLabel,
    required this.workLabel,
    required this.confidenceLabel,
  });

  final String title;
  final String? author;
  final String? work;
  final String confidence;
  final String explanation;
  final String authorLabel;
  final String workLabel;
  final String confidenceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if ((author ?? '').isNotEmpty) Text('$authorLabel$author'),
            if ((work ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('$workLabel$work'),
            ],
            const SizedBox(height: 6),
            Text('$confidenceLabel$confidence'),
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(explanation),
            ],
          ],
        ),
      ),
    );
  }
}

class AIInsightWorkflowCard extends StatelessWidget {
  const AIInsightWorkflowCard({
    super.key,
    required this.title,
    required this.analysisTypes,
    required this.analysisStyles,
    required this.selectedType,
    required this.selectedStyle,
    required this.onSelectType,
    required this.onSelectStyle,
    required this.onRun,
    required this.runLabel,
  });

  final String title;
  final Map<String, String> analysisTypes;
  final Map<String, String> analysisStyles;
  final String selectedType;
  final String selectedStyle;
  final ValueChanged<String> onSelectType;
  final ValueChanged<String> onSelectStyle;
  final VoidCallback onRun;
  final String runLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildChips({
      required Map<String, String> options,
      required String selected,
      required ValueChanged<String> onSelected,
    }) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.entries.map((entry) {
          return ChoiceChip(
            label: Text(entry.value),
            selected: entry.key == selected,
            onSelected: (_) => onSelected(entry.key),
          );
        }).toList(),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            buildChips(
              options: analysisTypes,
              selected: selectedType,
              onSelected: onSelectType,
            ),
            const SizedBox(height: 12),
            buildChips(
              options: analysisStyles,
              selected: selectedStyle,
              onSelected: onSelectStyle,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onRun,
                child: Text(runLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
