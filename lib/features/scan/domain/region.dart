enum RegionType {
  front, crown, leftSide, rightSide,
  upperLip, chin, jawline
}

class RegionBox {
  RegionBox(this.type, this.rectNormalized);
  final RegionType type;
  // Rect normalized to images bounding box: left, top, right, bottom in 0..1
  final ({double l, double t, double r, double b}) rectNormalized;
}
