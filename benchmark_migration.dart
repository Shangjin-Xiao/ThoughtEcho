import 'dart:io';
import 'package:path/path.dart' as path;

Future<void> copyFileInChunks(String source, String dest) async {
  final srcFile = File(source);
  final destFile = File(dest);
  await destFile.create(recursive: true);

  // Just simulate copying for benchmark
  await srcFile.copy(dest);
}

Future<void> simulateSequential(List<String> files) async {
  int copiedCount = 0;
  for (final filePath in files) {
    try {
      final destPath = filePath + ".dest";
      await copyFileInChunks(filePath, destPath);
      copiedCount++;
    } catch (e) {
      print(e);
    }
  }
}

Future<void> simulateParallel(List<String> files) async {
  int copiedCount = 0;
  // process in chunks of 5
  final chunkSize = 5;
  for (int i = 0; i < files.length; i += chunkSize) {
    final chunk = files.sublist(i, i + chunkSize > files.length ? files.length : i + chunkSize);
    await Future.wait(chunk.map((filePath) async {
      try {
        final destPath = filePath + ".dest";
        await copyFileInChunks(filePath, destPath);
      } catch (e) {
        print(e);
      }
    }));
  }
}

void main() async {
  // Create dummy files
  final dummyDir = Directory("dummy_files");
  await dummyDir.create();
  List<String> files = [];
  for (int i = 0; i < 100; i++) {
    final f = File(path.join(dummyDir.path, "file_$i.txt"));
    await f.writeAsString("This is a dummy file for benchmarking migrations $i");
    files.add(f.path);
  }

  // Benchmark Sequential
  final seqStart = DateTime.now();
  await simulateSequential(files);
  final seqTime = DateTime.now().difference(seqStart).inMilliseconds;
  print("Sequential time: $seqTime ms");

  // Benchmark Parallel
  final parStart = DateTime.now();
  await simulateParallel(files);
  final parTime = DateTime.now().difference(parStart).inMilliseconds;
  print("Parallel time: $parTime ms");

  await dummyDir.delete(recursive: true);
}
