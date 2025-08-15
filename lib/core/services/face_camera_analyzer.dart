import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:whiskrs/core/services/score_analyzer.dart';
import 'package:whiskrs/features/scan/domain/region.dart';
import 'package:whiskrs/features/scan/domain/scan_result.dart';

/// Optimized androgenic region detection for face_camera package
class FaceCameraRegionAnalyzer {
  // Pre-calculated constants to avoid repeated calculations
  static const double _minFaceWidth = 100.0;
  static const double _minFaceHeight = 120.0;
  static const double _maxYawAngle = 25.0;
  static const double _maxPitchAngle = 20.0;

  /// Generates androgenic regions from face detection - optimized version
  static List<RegionBox> androgenicRegions(Face face) {
    final box = face.boundingBox;
    final x0 = box.left.toDouble();
    final y0 = box.top.toDouble();
    final w = box.width.toDouble();
    final h = box.height.toDouble();

    // Landmarks with graceful fallbacks
    final lm = face.landmarks;
    final leftEye = lm[FaceLandmarkType.leftEye]?.position;
    final rightEye = lm[FaceLandmarkType.rightEye]?.position;
    final lMouth = lm[FaceLandmarkType.leftMouth]?.position;
    final rMouth = lm[FaceLandmarkType.rightMouth]?.position;
    final noseBase = lm[FaceLandmarkType.noseBase]?.position;

    final eyeL =
        leftEye != null
            ? Pt(leftEye.x.toDouble(), leftEye.y.toDouble())
            : Pt(x0 + w * 0.35, y0 + h * 0.4);
    final eyeR =
        rightEye != null
            ? Pt(rightEye.x.toDouble(), rightEye.y.toDouble())
            : Pt(x0 + w * 0.65, y0 + h * 0.4);
    final mouthCtr =
        (lMouth != null && rMouth != null)
            ? Pt((lMouth.x + rMouth.x) * 0.5, (lMouth.y + rMouth.y) * 0.5)
            : (noseBase != null
                ? Pt(noseBase.x.toDouble(), noseBase.y.toDouble() + h * 0.25)
                : Pt(x0 + w * 0.5, y0 + h * 0.7));

    // Compute transforms
    final toCanonical = fitSimilarity(
      eyeL,
      eyeR,
      mouthCtr,
      kLeftEyeC,
      kRightEyeC,
      kMouthCtrC,
    );
    final toImage = toCanonical.invert();

    // Map canonical rect to image coordinates and normalize
    Rect mapRect(CanonicalRect cr) {
      final pLT = toImage.apply(Pt(cr.l, cr.t));
      final pRB = toImage.apply(Pt(cr.r, cr.b));
      return Rect.fromLTRB(
        pLT.x.clamp(x0, x0 + w),
        pLT.y.clamp(y0, y0 + h),
        pRB.x.clamp(x0, x0 + w),
        pRB.y.clamp(y0, y0 + h),
      );
    }

    final invW = 1.0 / w;
    final invH = 1.0 / h;

    return canonicalRegions.entries.map((e) {
      final r = mapRect(e.value);
      return RegionBox(e.key, (
        l: (r.left - x0) * invW,
        t: (r.top - y0) * invH,
        r: (r.right - x0) * invW,
        b: (r.bottom - y0) * invH,
      ));
    }).toList();
  }

  /// Optimized face quality validation with early returns
  static String? _validateFaceQuality(Face face) {
    final box = face.boundingBox;

    // Size validation - early return on failure
    if (box.width < _minFaceWidth || box.height < _minFaceHeight) {
      return 'Face too small for analysis';
    }

    // Orientation validation with null-safe early returns
    final yaw = face.headEulerAngleY;
    if (yaw != null && yaw.abs() > _maxYawAngle) {
      return 'Face not facing forward (yaw: ${yaw.toStringAsFixed(1)}°)';
    }

    final pitch = face.headEulerAngleX;
    if (pitch != null && pitch.abs() > _maxPitchAngle) {
      return 'Face tilted too much (pitch: ${pitch.toStringAsFixed(1)}°)';
    }

    // Quick landmark check - only verify critical landmarks
    if (!face.landmarks.containsKey(FaceLandmarkType.leftEye) ||
        !face.landmarks.containsKey(FaceLandmarkType.rightEye)) {
      return 'Missing critical landmarks';
    }

    return null; // Quality acceptable
  }

  /// Streamlined analysis function
  static Future<ScanResult?> analyzeFaceCameraCapture({
    required File imageFile,
    required Face face,
    required double thrFront,
    required double thrCrown,
    required double thrSides,
    bool enableDebugMode = true,
  }) async {
    // Fast quality validation with early return
    final qualityIssue = _validateFaceQuality(face);
    if (qualityIssue != null) {
      if (enableDebugMode) print('Face quality insufficient: $qualityIssue');
      return null;
    }

    final bytes = await imageFile.readAsBytes();
    final src = img.decodeImage(bytes);
    if (src == null) {
      if (enableDebugMode) print('Error: Could not decode image');
      return null;
    }

    final start = DateTime.now();
    final facialRegions = androgenicRegions(face);
    final scores = <RegionScore>[];
    final fb = face.boundingBox;

    // Pre-calculate image dimensions and face bounds
    final imageWidth = src.width;
    final imageHeight = src.height;
    final faceLeft = fb.left.toDouble();
    final faceTop = fb.top.toDouble();
    final faceWidth = fb.width.toDouble();
    final faceHeight = fb.height.toDouble();

    if (enableDebugMode) {
      print('Face bounds: $faceLeft, $faceTop, $faceWidth, $faceHeight');
      print('Image size: ${imageWidth}x$imageHeight');
    }

    // Process regions with optimized coordinate transformation
    for (final rb in facialRegions) {
      final rect = rb.rectNormalized;

      // Direct coordinate calculation without helper classes
      final rx = (faceLeft + rect.l * faceWidth).round().clamp(
        0,
        imageWidth - 1,
      );
      final ry = (faceTop + rect.t * faceHeight).round().clamp(
        0,
        imageHeight - 1,
      );
      final rw = ((rect.r - rect.l) * faceWidth).round().clamp(
        1,
        imageWidth - rx,
      );
      final rh = ((rect.b - rect.t) * faceHeight).round().clamp(
        1,
        imageHeight - ry,
      );

      // Quick validation
      if (rw <= 3 || rh <= 3 || rx + rw > imageWidth || ry + rh > imageHeight) {
        if (enableDebugMode) {
          print(
            'Invalid region ${rb.type.name}: coords($rx,$ry) size(${rw}x$rh)',
          );
        }
        scores.add(RegionScore(rb.type, 0, false));
        continue;
      }

      try {
        final score = ImageRegionAnalyzer.scoreRegion(
          src: src,
          x: rx,
          y: ry,
          w: rw,
          h: rh,
          useBuiltinSobel: true,
        );

        // Inline threshold selection
        final threshold = switch (rb.type) {
          RegionType.front => thrFront,
          RegionType.crown => thrCrown,
          _ => thrSides, // All other regions use sides threshold
        };

        final passes = score >= threshold;
        scores.add(RegionScore(rb.type, score, passes));

        if (enableDebugMode) {
          print(
            '${rb.type.name}: score=${score.toStringAsFixed(3)}, '
            'threshold=${threshold.toStringAsFixed(3)}, pass=$passes',
          );
        }
      } catch (e) {
        if (enableDebugMode) print('Error analyzing ${rb.type.name}: $e');
        scores.add(RegionScore(rb.type, 0, false));
      }
    }

    final ms = DateTime.now().difference(start).inMilliseconds;
    return ScanResult(scores, ms);
  }

  // /// Optimized batch analysis with reduced object allocations
  // static Future<List<ScanResult?>> analyzeBatch({
  //   required List<File> imageFiles,
  //   required List<Face> faces,
  //   required double thrFront,
  //   required double thrCrown,
  //   required double thrSides,
  //   bool enableDebugMode = false,
  // }) async {
  //   assert(imageFiles.length == faces.length, 'Images and faces lists must have same length');
  //
  //   // Pre-allocate result list for better memory efficiency
  //   final results = <ScanResult?>[for (int i = 0; i < imageFiles.length; i++) null];
  //
  //   for (int i = 0; i < imageFiles.length; i++) {
  //     results[i] = await analyzeFaceCameraCapture(
  //       imageFile: imageFiles[i],
  //       face: faces[i],
  //       thrFront: thrFront,
  //       thrCrown: thrCrown,
  //       thrSides: thrSides,
  //       enableDebugMode: enableDebugMode,
  //     );
  //   }
  //
  //   return results;
  // }
}

// Simplified extension with optimized methods
// extension FaceCameraAnalysis on Face {
//   /// Quick analysis method with pre-validated quality check
//   Future<ScanResult?> analyzeAndrogenicRegions({
//     required File imageFile,
//     required double thrFront,
//     required double thrCrown,
//     required double thrSides,
//     bool enableDebugMode = false,
//   }) {
//     return FaceCameraRegionAnalyzer.analyzeFaceCameraCapture(
//       imageFile: imageFile,
//       face: this,
//       thrFront: thrFront,
//       thrCrown: thrCrown,
//       thrSides: thrSides,
//       enableDebugMode: enableDebugMode,
//     );
//   }
//
//   /// Cached regions getter
//   List<RegionBox> getAndrogenicRegions() {
//     return FaceCameraRegionAnalyzer.androgenicRegions(this);
//   }
//
//   /// Optimized quality check
//   bool get isGoodForAnalysis {
//     return FaceCameraRegionAnalyzer._validateFaceQuality(this) == null;
//   }
// }

// --- Geometry helpers ---
class Pt {
  final double x, y;

  const Pt(this.x, this.y);
}

class Mat2x3 {
  final double a, b, tx, ty;

  const Mat2x3(this.a, this.b, this.tx, this.ty);

  Pt apply(Pt p) => Pt(a * p.x - b * p.y + tx, b * p.x + a * p.y + ty);

  Mat2x3 invert() {
    final s2 = a * a + b * b;
    final ia = a / s2, ib = -b / s2;
    final itx = -(ia * tx - ib * ty);
    final ity = -(ib * tx + ia * ty);
    return Mat2x3(ia, -ib, itx, ity);
  }
}

Mat2x3 fitSimilarity(Pt s1, Pt s2, Pt s3, Pt t1, Pt t2, Pt t3) {
  Pt centroid(List<Pt> ps) => Pt(
    ps.fold(0.0, (a, p) => a + p.x) / ps.length,
    ps.fold(0.0, (a, p) => a + p.y) / ps.length,
  );
  List<Pt> c(List<Pt> ps, Pt c) =>
      ps.map((p) => Pt(p.x - c.x, p.y - c.y)).toList();

  final cs = centroid([s1, s2, s3]);
  final ct = centroid([t1, t2, t3]);
  final S = c([s1, s2, s3], cs);
  final T = c([t1, t2, t3], ct);

  double numA = 0, numB = 0, den = 0;
  for (var i = 0; i < 3; i++) {
    final sx = S[i].x, sy = S[i].y, tx = T[i].x, ty = T[i].y;
    numA += sx * tx + sy * ty;
    numB += sx * ty - sy * tx;
    den += sx * sx + sy * sy;
  }
  final a = numA / den;
  final b = numB / den;
  final tx = ct.x - (a * cs.x - b * cs.y);
  final ty = ct.y - (b * cs.x + a * cs.y);

  return Mat2x3(a, b, tx, ty);
}

// --- Canonical keypoints + templates ---
const Pt kLeftEyeC = Pt(-0.5, 0.0);
const Pt kRightEyeC = Pt(0.5, 0.0);
const Pt kMouthCtrC = Pt(0.0, 0.6);

class CanonicalRect {
  final double l, t, r, b;

  const CanonicalRect(this.l, this.t, this.r, this.b);
}

const canonicalRegions = {
  RegionType.front: CanonicalRect(-0.35, -0.35, 0.35, 0.15),
  RegionType.crown: CanonicalRect(-0.40, -0.90, 0.40, -0.40),
  RegionType.leftSide: CanonicalRect(-0.95, -0.10, -0.20, 0.70),
  RegionType.rightSide: CanonicalRect(0.20, -0.10, 0.95, 0.70),
  RegionType.upperLip: CanonicalRect(-0.20, 0.45, 0.20, 0.60),
  RegionType.chin: CanonicalRect(-0.30, 0.70, 0.30, 1.10),
  RegionType.jawline: CanonicalRect(-0.50, 0.40, 0.50, 0.95),
};
