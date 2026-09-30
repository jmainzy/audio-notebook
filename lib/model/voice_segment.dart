enum SegmentLanguage { mvskoke, english, mixed }

class Segment {
  /// The sequential internal identifier (0, 1, 2...)
  /// Critical for array lookups and UI list ordering.
  final int index;

  Segment({
    required this.index,
    required this.start,
    required this.end,
    this.text = "",
    this.language = SegmentLanguage.mixed,
  });

  double start;
  double end;
  final String text;
  final SegmentLanguage language;

  /// Helper to update real timing after alignment
  void setTiming({required double start, required double end}) {
    this.start = start;
    this.end = end;
  }
}
