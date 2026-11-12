import 'odds.dart';

/// A play the person saved to look at later. It is not a placed bet.
class SavedPlay {
  SavedPlay({
    required this.id,
    required this.savedAt,
    required this.title,
    required this.detail,
    required this.book,
    required this.demo,
    required this.priceNote,
    this.decimal,
    this.removed = false,
  }) {
    if (id.trim().isEmpty) throw ArgumentError('A saved play needs an id.');
    if (title.trim().isEmpty) throw ArgumentError('A saved play needs a title.');
    if (decimal != null) impliedProbability(decimal!);
  }

  final String id, title, detail, book, priceNote;
  final DateTime savedAt;
  final double? decimal;
  final bool demo;

  /// A later write with this set drops the play from the shortlist.
  final bool removed;

  SavedPlay copyWith({bool? removed}) => SavedPlay(
    id: id,
    savedAt: savedAt,
    title: title,
    detail: detail,
    book: book,
    demo: demo,
    priceNote: priceNote,
    decimal: decimal,
    removed: removed ?? this.removed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'title': title,
    'detail': detail,
    'book': book,
    'decimal': decimal,
    'demo': demo,
    'priceNote': priceNote,
    'removed': removed,
  };

  factory SavedPlay.fromJson(Map<String, dynamic> json) {
    final saved = json['savedAt'];
    if (saved is! String) {
      throw const FormatException('Saved play needs a timestamp.');
    }
    final title = json['title'];
    final id = json['id'];
    if (id is! String || title is! String) {
      throw const FormatException('Saved play needs an id and a title.');
    }
    final decimal = json['decimal'];
    if (decimal != null && decimal is! num) {
      throw const FormatException('Saved play price must be a number.');
    }
    final demo = json['demo'];
    if (demo is! bool) {
      throw const FormatException('Saved play demo flag must be true or false.');
    }
    return SavedPlay(
      id: id,
      savedAt: DateTime.parse(saved),
      title: title,
      detail: '${json['detail'] ?? ''}',
      book: '${json['book'] ?? ''}',
      decimal: (decimal as num?)?.toDouble(),
      demo: demo,
      priceNote: '${json['priceNote'] ?? ''}',
      removed: json['removed'] == true,
    );
  }
}
