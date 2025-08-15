import 'region.dart';

class RegionScore {
  RegionScore(this.type, this.score, this.passed);
  final RegionType type;
  final double score; // 0..1 density score
  final bool passed;
}

class ScanResult {
  ScanResult(this.regionScores, this.captureMs);
  final List<RegionScore> regionScores;
  final int captureMs;
}
