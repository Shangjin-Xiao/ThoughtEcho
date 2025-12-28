import 'package:objectbox/objectbox.dart';

@Entity()
class NoteVector {
  @Id()
  int id = 0;

  @Index()
  @Unique()
  String quoteId;

  @HnswIndex(dimensions: 384)
  List<double> embedding;

  NoteVector({
    this.id = 0,
    required this.quoteId,
    required this.embedding,
  });
}
