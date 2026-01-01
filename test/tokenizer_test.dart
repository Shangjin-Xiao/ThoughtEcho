import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:thoughtecho/utils/bert_tokenizer.dart';

void main() {
  test('BertTokenizer tokenization test', () async {
    // Create a temporary vocab file
    final vocabContent = """
[PAD]
[UNK]
[CLS]
[SEP]
[MASK]
hello
world
##ing
test
""";
    final tempDir = Directory.systemTemp.createTempSync('tokenizer_test');
    final vocabFile = File('${tempDir.path}/vocab.txt');
    await vocabFile.writeAsString(vocabContent);

    final tokenizer = await BertTokenizer.fromFile(vocabFile.path);

    // Test simple tokenization
    final tokens = tokenizer.tokenize("hello world");
    expect(tokens.length, 4); // [CLS], hello, world, [SEP]
    expect(tokens[1], 5); // hello
    expect(tokens[2], 6); // world

    // Test subword tokenization (mock logic, our simple vocab has ##ing)
    // Note: real bert tokenization is complex, this test verifies our logic works for the provided vocab
    // "testing" -> test, ##ing
    // vocab: test=8, ##ing=7
    final tokens2 = tokenizer.tokenize("testing");
    // Depending on logic: "testing" is not in vocab.
    // "test" (idx 8)
    // "##ing" (idx 7)
    // expected: [CLS], test, ##ing, [SEP]
    expect(tokens2[1], 8);
    expect(tokens2[2], 7);

    // Clean up
    tempDir.deleteSync(recursive: true);
  });
}
