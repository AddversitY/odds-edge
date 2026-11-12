import 'dart:io';
import 'dart:typed_data';

import 'text_journal.dart';

TextJournal createJournal(Object? directory) {
  if (directory != null && directory is! Directory) {
    throw ArgumentError('Pass a Directory, or omit it.');
  }
  return IoJournal(directory as Directory?);
}

class IoJournal implements TextJournal {
  IoJournal(this.directory);
  final Directory? directory;

  Future<Directory> _folder() async {
    final root = directory ?? _supportDirectory();
    final folder = Directory('${root.path}${Platform.pathSeparator}odds_edge');
    await folder.create(recursive: true);
    return folder;
  }

  Directory _supportDirectory() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['LOCALAPPDATA'];
      if (appData != null && appData.isNotEmpty) return Directory(appData);
    } else if (Platform.isIOS || Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/Library/Application Support');
      }
    }
    throw StateError('Application support directory unavailable');
  }

  Future<File> _file(String name) async {
    final folder = await _folder();
    return File('${folder.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<Uint8List?> readBytes(String name) async {
    final file = await _file(name);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> append(String name, String text) async {
    final file = await _file(name);
    await file.writeAsString(text, mode: FileMode.append, flush: true);
  }

  @override
  Future<String> makeBackup({
    required String researchName,
    required List<String> copies,
  }) async {
    final folder = await _folder();
    final separator = Platform.pathSeparator;
    final source = File('${folder.path}$separator$researchName');
    final target = File(
      '${folder.path}${separator}research-backup-${DateTime.now().microsecondsSinceEpoch}.jsonl',
    );
    await target.writeAsBytes(
      await source.exists() ? await source.readAsBytes() : <int>[],
      flush: true,
    );
    for (final name in copies) {
      final file = File('${folder.path}$separator$name');
      if (!await file.exists()) continue;
      // Reviews keep the historical ".reviews" suffix. Other journals keep
      // their file name, which is what the existing backup tests check.
      final suffix = name == 'reviews.jsonl' ? 'reviews' : name;
      await file.copy('${target.path}.$suffix');
    }
    return target.path;
  }
}
