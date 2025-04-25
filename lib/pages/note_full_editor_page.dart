import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NoteFullEditorPage extends StatefulWidget {
  final String initialContent;
  const NoteFullEditorPage({super.key, required this.initialContent});

  @override
  State<NoteFullEditorPage> createState() => _NoteFullEditorPageState();
}

class _NoteFullEditorPageState extends State<NoteFullEditorPage> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存并返回',
            onPressed: () {
              Navigator.pop(context, _controller.text);
            },
          ),
        ],
        automaticallyImplyLeading: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: TextField(
          controller: _controller,
          maxLines: null,
          autofocus: true,
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.7),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '',
            isCollapsed: true,
            contentPadding: EdgeInsets.zero,
          ),
          keyboardType: TextInputType.multiline,
        ),
      ),
    );
  }
} 