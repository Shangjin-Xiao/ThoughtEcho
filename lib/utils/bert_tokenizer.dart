import 'dart:io';

class BertTokenizer {
  final Map<String, int> vocab;
  final bool doLowerCase;

  BertTokenizer(this.vocab, {this.doLowerCase = true});

  static Future<BertTokenizer> fromFile(String vocabPath, {bool doLowerCase = true}) async {
    final file = File(vocabPath);
    if (!await file.exists()) {
      throw Exception("Vocab file not found at $vocabPath");
    }
    final lines = await file.readAsLines();
    final vocab = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      vocab[lines[i].trim()] = i;
    }
    return BertTokenizer(vocab, doLowerCase: doLowerCase);
  }

  List<int> tokenize(String text, {int maxLen = 512}) {
    // 1. Basic cleaning and splitting
    if (doLowerCase) {
      text = text.toLowerCase();
    }
    // Simple whitespace tokenization
    final basicTokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // 2. WordPiece tokenization
    final List<int> ids = [];
    ids.add(vocab['[CLS]'] ?? 101); // [CLS]

    for (var token in basicTokens) {
      if (ids.length >= maxLen - 1) break; // Reserve space for [SEP]

      final subTokens = _wordPieceTokenize(token);
      for (var subToken in subTokens) {
        if (ids.length >= maxLen - 1) break;
        ids.add(vocab[subToken] ?? (vocab['[UNK]'] ?? 100));
      }
    }

    ids.add(vocab['[SEP]'] ?? 102); // [SEP]
    return ids;
  }

  List<String> _wordPieceTokenize(String text) {
    if (text.isEmpty) return [];

    // Check if the full token is in vocab
    if (vocab.containsKey(text)) {
      return [text];
    }

    // WordPiece algorithm
    final List<String> outputTokens = [];
    bool isBad = false;
    int start = 0;

    while (start < text.length) {
      int end = text.length;
      String? curSubStr;

      while (start < end) {
        String subStr = text.substring(start, end);
        if (start > 0) {
          subStr = "##$subStr";
        }
        if (vocab.containsKey(subStr)) {
          curSubStr = subStr;
          break;
        }
        end--;
      }

      if (curSubStr == null) {
        isBad = true;
        break;
      }

      outputTokens.add(curSubStr);
      start = end;
    }

    if (isBad) {
      return [text]; // Fallback: keep original or map to UNK (handled in caller)
    }
    return outputTokens;
  }
}
