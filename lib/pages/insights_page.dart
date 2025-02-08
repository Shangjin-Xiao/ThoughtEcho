import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';

class InsightsPage extends StatefulWidget {
  const InsightsPage({Key? key}) : super(key: key);

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  bool _isLoading = false;
  String _insights = '';

  Future<void> _generateInsights() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final databaseService = context.read<DatabaseService>();
      final aiService = context.read<AIService>();

      final quotes = await databaseService.getUserQuotes();
      if (!mounted) return;

      if (quotes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有找到笔记，请先添加一些笔记'),
          ),
        );
        return;
      }

      final insights = await aiService.generateInsights(quotes);
      if (!mounted) return;

      setState(() {
        _insights = insights;
      });

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('生成洞察时出错：$e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('洞察'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : _generateInsights,
              child: const Text('生成洞察'),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_insights.isNotEmpty)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    ListTile(
                      title: Text(_insights),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}