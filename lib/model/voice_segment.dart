class Segment {
  /// The sequential internal identifier (0, 1, 2...)
  /// Critical for array lookups and UI list ordering.
  final int index;

  const Segment({
    required this.index,
    required this.start,
    required this.end,
    this.text = "",
  });

  final double start;
  final double end;
  final String text;

  /// Helper to update real timing after alignment
  void setTiming({required double start, required double end}) {
    start = start;
    end = end;
  }
}
