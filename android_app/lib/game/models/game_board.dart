import 'dart:math';

enum GemType {
  cyan,
  neonPink,
  electricGreen,
  amber,
  purple;

  static GemType random(Random rng) {
    return GemType.values[rng.nextInt(GemType.values.length)];
  }
}

class GemTile {
  final int row;
  final int col;
  final GemType type;
  final bool isMatched;

  const GemTile({
    required this.row,
    required this.col,
    required this.type,
    this.isMatched = false,
  });

  GemTile copyWith({
    int? row,
    int? col,
    GemType? type,
    bool? isMatched,
  }) {
    return GemTile(
      row: row ?? this.row,
      col: col ?? this.col,
      type: type ?? this.type,
      isMatched: isMatched ?? this.isMatched,
    );
  }
}
