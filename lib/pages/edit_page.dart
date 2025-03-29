import 'package:flutter/material.dart';
import 'package:mind_trace/models/quote_model.dart';
import 'package:mind_trace/services/ai_service.dart';
import 'package:mind_trace/services/database_service.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class EditPage extends StatefulWidget {
  final Quote quote;

  const EditPage({Key? key, required this.quote}) : super(key: key);

  @override
  _EditPageState createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late TextEditingController _contentController;
  late TextEditingController _authorController;
  late TextEditingController _workController;
  late String _aiAnalysis;
  late List<String> _tagIds;
  late String? _colorHex;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.quote.content);
    
    // 从source解析出author和work（如果它们为空）
    String author = widget.quote.sourceAuthor ?? '';
    String work = widget.quote.sourceWork ?? '';
    
    if ((author.isEmpty || work.isEmpty) && widget.quote.source != null) {
      _parseSource(widget.quote.source!);
    }
    
    _authorController = TextEditingController(text: author);
    _workController = TextEditingController(text: work);
    _aiAnalysis = widget.quote.aiAnalysis ?? '';
    _tagIds = List<String>.from(widget.quote.tagIds ?? []);
    _colorHex = widget.quote.colorHex;
  }

  void _parseSource(String source) {
    // 尝试解析格式如"——作者「作品」"的字符串
    String author = '';
    String work = '';
    
    // 提取作者（在"——"之后，"「"之前）
    final authorMatch = RegExp(r'——([^「]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }
    
    // 提取作品（在「」之间）
    final workMatch = RegExp(r'「(.+?)」').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }
    
    _authorController.text = author;
    _workController.text = work;
  }

  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }
    
    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }
    
    if (work.isNotEmpty) {
      result += ' 「$work」';
    }
    
    return result;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _authorController.dispose();
    _workController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final databaseService = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              // 保存编辑后的笔记
              final newQuote = Quote(
                id: widget.quote.id,
                content: _contentController.text,
                date: widget.quote.date,
                aiAnalysis: _aiAnalysis,
                source: _formatSource(_authorController.text, _workController.text),
                sourceAuthor: _authorController.text,
                sourceWork: _workController.text,
                tagIds: _tagIds,
                colorHex: _colorHex,
              );

              await databaseService.updateQuote(newQuote);
              
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('保存成功！')),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: '内容',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _authorController,
                    decoration: const InputDecoration(
                      labelText: '作者/人物',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _workController,
                    decoration: const InputDecoration(
                      labelText: '作品名称',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.book),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '将显示为: ${_formatSource(_authorController.text, _workController.text)}',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            const Text('AI 分析:'),
            Text(_aiAnalysis.isEmpty ? '暂无分析' : _aiAnalysis),
            
            // 添加标签和颜色选择的UI控件
            // ...

            // 测试用的AI分析按钮
            ElevatedButton(
              onPressed: () async {
                final aiService = Provider.of<AIService>(context, listen: false);
                final summary = await aiService.summarizeNote(
                  Quote(
                    id: widget.quote.id,
                    content: _contentController.text,
                    date: widget.quote.date,
                  ),
                );
                setState(() {
                  _aiAnalysis = summary ?? '';
                });
              },
              child: const Text('生成AI分析'),
            ),
          ],
        ),
      ),
    );
  }
} 