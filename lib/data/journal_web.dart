import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'text_journal.dart';

TextJournal createJournal(Object? directory) => WebJournal();

/// One localStorage key per journal. Enough for notes on a phone browser.
/// A full desktop backup still uses the file journal.
class WebJournal implements TextJournal {
  static const _prefix = 'odds_edge/';

  String _key(String name) => '$_prefix$name';

  @override
  Future<Uint8List?> readBytes(String name) async {
    final text = window.localStorage.getItem(_key(name));
    if (text == null) return null;
    return Uint8List.fromList(utf8.encode(text));
  }

  @override
  Future<void> append(String name, String text) async {
    final current = window.localStorage.getItem(_key(name)) ?? '';
    window.localStorage.setItem(_key(name), '$current$text');
  }

  @override
  Future<String> makeBackup({
    required String researchName,
    required List<String> copies,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final target = 'research-backup-$stamp.jsonl';
    final source = window.localStorage.getItem(_key(researchName)) ?? '';
    window.localStorage.setItem(_key(target), source);
    for (final name in copies) {
      final text = window.localStorage.getItem(_key(name));
      if (text == null) continue;
      final suffix = name == 'reviews.jsonl' ? 'reviews' : name;
      window.localStorage.setItem(_key('$target.$suffix'), text);
    }
    return target;
  }
}
