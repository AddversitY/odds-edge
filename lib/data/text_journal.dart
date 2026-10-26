import 'dart:typed_data';

/// Byte journals for research notes. The VM writes files. The browser writes
/// local storage. Callers never import dart:io.
abstract class TextJournal {
  Future<Uint8List?> readBytes(String name);
  Future<void> append(String name, String text);

  /// Copies the research file and the named journals. Returns the research
  /// backup path (or a storage key on the web).
  Future<String> makeBackup({
    required String researchName,
    required List<String> copies,
  });
}
