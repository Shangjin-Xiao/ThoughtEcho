part of 'smart_result_card.dart';

extension _SmartResultCardEditing on _SmartResultCardState {
  List<String> get _draftTagNames => _tagsController.text
      .split(RegExp(r'[,，、]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  Future<void> _editTextValue({
    required String title,
    required TextEditingController controller,
    int maxLines = 1,
  }) async {
    final editor = TextEditingController(text: controller.text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: editor,
          autofocus: true,
          minLines: maxLines == 1 ? 1 : 4,
          maxLines: maxLines,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editor.text),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    Future<void>.delayed(
      const Duration(milliseconds: 400),
      editor.dispose,
    );
    if (value == null || !mounted) return;
    _updateDraft(() => controller.text = value);
  }

  Future<void> _editMetadata() async {
    final l10n = AppLocalizations.of(context);
    final author = TextEditingController(text: _authorController.text);
    final source = TextEditingController(text: _sourceController.text);
    final available =
        await widget.loadAvailableTagNames?.call() ?? _draftTagNames;
    if (!mounted) return;
    final selected = _draftTagNames.toSet();
    final result =
        await showDialog<({String author, String source, List<String> tags})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.editMetadata),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: author,
                  decoration: InputDecoration(labelText: l10n.author),
                ),
                TextField(
                  controller: source,
                  decoration: InputDecoration(labelText: l10n.source),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(l10n.tagsLabel),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final tag in {...available, ...selected})
                      FilterChip(
                        label: Text(tag),
                        selected: selected.contains(tag),
                        onSelected: (value) => setDialogState(() {
                          value ? selected.add(tag) : selected.remove(tag);
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                (
                  author: author.text,
                  source: source.text,
                  tags: selected.toList(),
                ),
              ),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      author.dispose();
      source.dispose();
    });
    if (result == null || !mounted) return;
    _updateDraft(() {
      _authorController.text = result.author;
      _sourceController.text = result.source;
      _tagsController.text = result.tags.join(', ');
    });
  }
}
