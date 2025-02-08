import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../widgets/sliding_card.dart';
import '../models/quote_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String dailyQuote = '加载中...';
  String userQuote = '';

  @override
  void initState() {
    super.initState();
    _fetchDailyQuote();
  }

  Future<void> _fetchDailyQuote() async {
    final quote = await ApiService.getDailyQuote();
    setState(() {
      dailyQuote = quote;
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('每日一言')),
      body: Column(
        children: [
          Expanded(
            child: SlidingCard(
              pages: [
                Center(child: Text(dailyQuote, style: const TextStyle(fontSize: 24))),
                Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(hintText: '输入你的每日一言'),
                      onChanged: (value) => userQuote = value,
                    ),
                    ElevatedButton(
                      onPressed: () {
                        db.saveUserQuote(userQuote);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('保存成功！')),
                        );
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Quote>>(
              future: db.getAllQuotes(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final quotes = snapshot.data!;
                return ListView.builder(
                  itemCount: quotes.length,
                  itemBuilder: (context, index) {
                    final quote = quotes[index];
                    return ListTile(
                      title: Text(quote.content),
                      subtitle: Text(quote.date),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}