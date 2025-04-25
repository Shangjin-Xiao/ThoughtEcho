import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/database_service.dart';
import '../models/quote_model.dart';

class NoteFullEditorPage extends StatefulWidget {
  final String initialContent;
  final Quote? initialQuote;
  const NoteFullEditorPage({super.key, required this.initialContent, this.initialQuote});

  @override
  State<NoteFullEditorPage> createState() => _NoteFullEditorPageState();
}

class _NoteFullEditorPageState extends State<NoteFullEditorPage> {
  late quill.QuillController _controller;

  @override
  void initState() {
    super.initState();
    // 尝试将initialContent作为Delta解析，否则作为纯文本插入
    try {
      final document = quill.Document.fromJson(jsonDecode(widget.initialContent));
      _controller = quill.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      _controller = quill.QuillController(
        document: quill.Document()..insert(0, widget.initialContent),
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  Future<void> _saveContent() async {
    final db = Provider.of<DatabaseService>(context, listen: false);
    final deltaJson = jsonEncode(_controller.document.toDelta().toJson());
    final now = DateTime.now().toIso8601String();
    final Quote quote = Quote(
      id: widget.initialQuote?.id ?? const Uuid().v4(),
      content: deltaJson,
      date: widget.initialQuote?.date ?? now,
      source: widget.initialQuote?.source,
      sourceAuthor: widget.initialQuote?.sourceAuthor,
      sourceWork: widget.initialQuote?.sourceWork,
      aiAnalysis: widget.initialQuote?.aiAnalysis,
      sentiment: widget.initialQuote?.sentiment,
      keywords: widget.initialQuote?.keywords,
      summary: widget.initialQuote?.summary,
      tagIds: widget.initialQuote?.tagIds ?? [],
      categoryId: widget.initialQuote?.categoryId,
      colorHex: widget.initialQuote?.colorHex,
      location: widget.initialQuote?.location,
      weather: widget.initialQuote?.weather,
      temperature: widget.initialQuote?.temperature,
    );
    try {
      if (widget.initialQuote != null) {
        await db.updateQuote(quote);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('笔记已更新')),
          );
        }
      } else {
        await db.addQuote(quote);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('笔记已保存')),
          );
        }
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '保存',
            onPressed: _saveContent,
          ),
        ],
        automaticallyImplyLeading: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            quill.QuillSimpleToolbar(controller: _controller),
            Expanded(
              child: Container(
                color: theme.colorScheme.surface,
                child: quill.QuillEditor.basic(
                  controller: _controller,
                  config: const quill.QuillEditorConfig(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 