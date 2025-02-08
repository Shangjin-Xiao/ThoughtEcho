class Quote {
  final int? id;
  final String date;
  final String content;

  Quote({
    this.id,
    required this.date,
    required this.content,
  });

  factory Quote.fromMap(Map<String, dynamic> map) {
    return Quote(
      id: map['id'] as int?,
      date: map['date'] as String,
      content: map['content'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'content': content,
    };
  }
}
