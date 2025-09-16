import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:whiskrs/core/services/score_analyzer.dart';
import 'package:whiskrs/features/scan/domain/region.dart';
import 'package:whiskrs/features/scan/domain/scan_result.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'dart:typed_data';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

/// Optimized face region analyzer for androgenic scoring
class FaceCameraRegionAnalyzer {
  // Minimum face dimensions
  static const double _minFaceWidth = 100.0;
  static const double _minFaceHeight = 120.0;

  // Maximum head rotation angles
  static const double _maxYawAngle = 25.0;
  static const double _maxPitchAngle = 20.0;

  // Default scoring weights
  static const double _defaultEdgeWeight = 0.7;
  static const double _defaultDarknessWeight = 0.3;
  static const double _defaultSaturationPower = 1.5;
  static const double _defaultPercentileThreshold = 0.35;

  /// Redetect face in cropped image for better landmarks
  static Future<Face?> _redetectFaceInCrop(img.Image croppedImage) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        enableClassification: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.1,
      ),
    );

    try {
      final imageBytes = img.encodeJpg(croppedImage, quality: 95);
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/temp_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFile(tempFile);
      final faces = await detector.processImage(inputImage);

      detector.close();
      tempFile.deleteSync();

      if (faces.isNotEmpty) {
        faces.sort(
          (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
            a.boundingBox.width * a.boundingBox.height,
          ),
        );
        return faces.first;
      }
    } catch (e) {
      detector.close();
    }
    return null;
  }

  /// Analyze face after cropping
  static Future<ScanResult?> _analyzeCroppedFace(
    img.Image src,
    Face face,
    double thrFront,
    double thrCrown,
    double thrSides,
    bool enableDebugMode,
  ) async {
    final start = DateTime.now();

    try {
      final croppedFace = _cropFaceExact(src, face);

      if (croppedFace == null) return null;

      final redetectedFace = await _redetectFaceInCrop(croppedFace);
      if (redetectedFace == null) return null;

      if (enableDebugMode) {
        print(
          'Cropped face: ${croppedFace.width}x${croppedFace.height}, original: ${src.width}x${src.height}',
        );
      }

      final regions = androgenicRegions(redetectedFace);
      final scores = await _analyzeRegions(
        croppedFace,
        redetectedFace,
        regions,
        thrFront,
        thrCrown,
        thrSides,
        enableDebugMode,
      );

      final ms = DateTime.now().difference(start).inMilliseconds;
      return ScanResult(scores, ms);
    } catch (e) {
      if (enableDebugMode) print('Error analyzing face: $e');
      return null;
    }
  }

  /// Region scoring with enhanced parameters
  static double _scoreRegionEnhanced(
    img.Image image,
    int x,
    int y,
    int w,
    int h,
    RegionType regionType,
  ) {
    double edgeWeight = _defaultEdgeWeight;
    double darknessWeight = _defaultDarknessWeight;
    double saturationPower = _defaultSaturationPower;
    double percentileThreshold = _defaultPercentileThreshold;

    switch (regionType) {
      case RegionType.upperLip:
        edgeWeight = 0.8;
        darknessWeight = 0.2;
        saturationPower = 1.6;
        percentileThreshold = 0.3;
        break;
      case RegionType.jawline:
        edgeWeight = 0.6;
        darknessWeight = 0.4;
        saturationPower = 1.3;
        break;
      case RegionType.crown:
        edgeWeight = 0.65;
        darknessWeight = 0.35;
        break;
      case RegionType.chin:
        edgeWeight = 0.5;
        darknessWeight = 0.5;
        saturationPower = 1.2;
        percentileThreshold = 0.7; // stricter
        break;
      default:
        break;
    }

    return ImageRegionAnalyzer.scoreRegion(
      src: image,
      x: x,
      y: y,
      w: w,
      h: h,
      edgeWeight: edgeWeight,
      darknessWeight: darknessWeight,
      saturationPower: saturationPower,
      percentileThreshold: percentileThreshold,
      useBuiltinSobel: true,
    );
  }

  /// Adaptive thresholds per region
  static double _getAdaptiveThreshold(
    RegionType type,
    double thrFront,
    double thrCrown,
    double thrSides,
    Rect box,
  ) {
    switch (type) {
      case RegionType.front:
        return thrFront;
      case RegionType.crown:
        return thrCrown;
      case RegionType.leftSide:
      case RegionType.rightSide:
        return thrSides;
      case RegionType.upperLip:
        return (thrFront * 1.25).clamp(0.7, 0.95);
      case RegionType.chin:
        return (thrFront * 0.75).clamp(0.5, 0.65);
      default:
        return thrFront;
    }
  }

  /// Analyze all regions
  static Future<List<RegionScore>> _analyzeRegions(
    img.Image image,
    Face face,
    List<RegionBox> regions,
    double thrFront,
    double thrCrown,
    double thrSides,
    bool enableDebugMode,
  ) async {
    final scores = <RegionScore>[];
    final box = face.boundingBox;

    for (final rb in regions) {
      final rect = rb.rectNormalized;

      final rx = (box.left + rect.l * box.width).round().clamp(
        0,
        image.width - 1,
      );
      final ry = (box.top + rect.t * box.height).round().clamp(
        0,
        image.height - 1,
      );
      final rw = ((rect.r - rect.l) * box.width).round().clamp(
        1,
        image.width - rx,
      );
      final rh = ((rect.b - rect.t) * box.height).round().clamp(
        1,
        image.height - ry,
      );

      if (rw <= 5 ||
          rh <= 5 ||
          rx + rw > image.width ||
          ry + rh > image.height) {
        if (enableDebugMode) {
          print(
            'Invalid region ${rb.type.name}: coords($rx,$ry) size(${rw}x$rh)',
          );
        }
        scores.add(RegionScore(rb.type, 0, false));
        continue;
      }

      try {
        final rawScore = _scoreRegionEnhanced(image, rx, ry, rw, rh, rb.type);
        final threshold = _getAdaptiveThreshold(
          rb.type,
          thrFront,
          thrCrown,
          thrSides,
          box,
        );
        final score = rawScore.clamp(0.0, 1.0);
        final passes = score >= threshold;

        scores.add(RegionScore(rb.type, score, passes));

        if (enableDebugMode) {
          print(
            '${rb.type.name}: raw=${rawScore.toStringAsFixed(3)}, clamped=${score.toStringAsFixed(3)}, threshold=${threshold.toStringAsFixed(3)}, pass=$passes',
          );
        }
      } catch (e) {
        if (enableDebugMode) print('Error analyzing ${rb.type.name}: $e');
        scores.add(RegionScore(rb.type, 0, false));
      }
    }

    return scores;
  }

  Future<img.Image?> extractFaceSegment(
    File imageFile,
    Face face, {
    bool enableDebug = false,
  }) async {
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final mask = await segmenter.processImage(inputImage);
      if (mask == null) {
        if (enableDebug) print('Segmentation returned null mask');
        return null;
      }

      final originalBytes = await imageFile.readAsBytes();
      final original = img.decodeImage(originalBytes);
      if (original == null) {
        if (enableDebug) print('Could not decode original image');
        return null;
      }

      final int width = original.width;
      final int height = original.height;
      final int maskWidth = mask.width;
      final int maskHeight = mask.height;

      final out = img.Image(width: width, height: height);

      // Attempt to read mask values as Float32List or Uint8List (many bindings differ)
      Float32List? floatMask;
      Uint8List? byteMask;
      try {
        final dynamic d = (mask as dynamic).data;
        if (d is Float32List && d.length >= maskWidth * maskHeight) {
          floatMask = d;
          if (enableDebug) print('Using mask.data as Float32List');
        }
      } catch (_) {}
      if (floatMask == null) {
        try {
          final dynamic buf = (mask as dynamic).buffer;
          if (buf is ByteBuffer) {
            final u = buf.asUint8List();
            if (u.length >= maskWidth * maskHeight) {
              byteMask = u;
              if (enableDebug) print('Using mask.buffer.asUint8List()');
            }
          }
        } catch (_) {}
      }
      if (floatMask == null && byteMask == null) {
        try {
          final dynamic b = (mask as dynamic).bytes;
          if (b is Uint8List && b.length >= maskWidth * maskHeight) {
            byteMask = b;
            if (enableDebug) print('Using mask.bytes (Uint8List)');
          }
        } catch (_) {}
      }
      if (floatMask == null && byteMask == null) {
        if (enableDebug) {
          print(
            'Cannot find mask data on SegmentationMask. Inspect mask at runtime.',
          );
        }
        return null;
      }

      // Pixel loop - map mask -> original image coords
      for (int y = 0; y < height; y++) {
        final int my = ((y / height) * maskHeight).toInt().clamp(
          0,
          maskHeight - 1,
        );
        for (int x = 0; x < width; x++) {
          final int mx = ((x / width) * maskWidth).toInt().clamp(
            0,
            maskWidth - 1,
          );
          final int maskIndex = my * maskWidth + mx;

          int alpha;
          if (floatMask != null) {
            final double v = floatMask[maskIndex];
            alpha = (v * 255.0).round().clamp(0, 255);
          } else {
            alpha = byteMask![maskIndex].clamp(0, 255);
          }

          // Robust extraction of r,g,b from original.getPixel
          final dynamic rawPixel = original.getPixel(x, y);
          int r = 0, g = 0, b = 0;

          if (rawPixel is int) {
            // older image package behavior: pixel is int (ARGB or RGBA depending on version)
            // Common layout: 0xAARRGGBB or 0xRRGGBBAA - this is best-effort; we assume AARRGGBB
            r = (rawPixel >> 16) & 0xFF;
            g = (rawPixel >> 8) & 0xFF;
            b = rawPixel & 0xFF;
          } else {
            // newer behavior: Pixel-like object with properties
            try {
              final dyn = rawPixel as dynamic;
              // try common property names
              if (dyn.r != null && dyn.g != null && dyn.b != null) {
                r = (dyn.r as int);
                g = (dyn.g as int);
                b = (dyn.b as int);
              } else if (dyn.red != null &&
                  dyn.green != null &&
                  dyn.blue != null) {
                r = (dyn.red as int);
                g = (dyn.green as int);
                b = (dyn.blue as int);
              } else {
                // Last fallback: try to call toUint32 or value getter
                try {
                  final maybeInt = dyn.toInt();
                  if (maybeInt is int) {
                    r = (maybeInt >> 16) & 0xFF;
                    g = (maybeInt >> 8) & 0xFF;
                    b = maybeInt & 0xFF;
                  }
                } catch (_) {
                  // leave r/g/b as zero if we can't read
                }
              }
            } catch (_) {
              // ignore and keep defaults
            }
          }

          out.setPixelRgba(
            x,
            y,
            r.clamp(0, 255),
            g.clamp(0, 255),
            b.clamp(0, 255),
            alpha,
          );
        }
      }

      // Crop face box from masked image using your existing crop method
      final cropped = FaceCameraRegionAnalyzer._cropFaceExact(out, face);
      return cropped;
    } finally {
      try {
        await segmenter.close();
      } catch (_) {}
    }
  }

  /// Crop face with more top, less bottom (reduces chin influence)
  static img.Image? _cropFaceExact(img.Image src, Face face) {
    final box = face.boundingBox;

    // Clamp bounding box to image dimensions
    final cropLeft = box.left.clamp(0.0, src.width.toDouble()).toInt();
    final cropTop = box.top.clamp(0.0, src.height.toDouble()).toInt();
    final cropWidth =
        box.width.clamp(1.0, src.width - cropLeft.toDouble()).toInt();
    final cropHeight =
        box.height.clamp(1.0, src.height - cropTop.toDouble()).toInt();

    if (cropWidth <= 0 || cropHeight <= 0) return null;

    return img.copyCrop(
      src,
      x: cropLeft,
      y: cropTop,
      width: cropWidth,
      height: cropHeight,
    );
  }

  /// Generate canonical androgenic regions
  static List<RegionBox> androgenicRegions(Face face) {
    final box = face.boundingBox;
    final x0 = box.left.toDouble();
    final y0 = box.top.toDouble();
    final w = box.width.toDouble();
    final h = box.height.toDouble();

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

    final toCanonical = fitSimilarity(
      eyeL,
      eyeR,
      mouthCtr,
      kLeftEyeC,
      kRightEyeC,
      kMouthCtrC,
    );
    final toImage = toCanonical.invert();

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

  /// Validate face quality
  static String? _validateFaceQuality(Face face) {
    final box = face.boundingBox;

    if (box.width < _minFaceWidth || box.height < _minFaceHeight)
      return 'Face too small';
    final yaw = face.headEulerAngleY;
    if (yaw != null && yaw.abs() > _maxYawAngle)
      return 'Face not facing forward';
    final pitch = face.headEulerAngleX;
    if (pitch != null && pitch.abs() > _maxPitchAngle)
      return 'Face tilted too much';
    if (!face.landmarks.containsKey(FaceLandmarkType.leftEye) ||
        !face.landmarks.containsKey(FaceLandmarkType.rightEye))
      return 'Missing critical landmarks';

    return null;
  }

  /// Main analysis function
  static Future<ScanResult?> analyzeFaceCameraCapture({
    required File imageFile,
    required Face face,
    required double thrFront,
    required double thrCrown,
    required double thrSides,
    bool enableDebugMode = true,
  }) async {
    final qualityIssue = _validateFaceQuality(face);
    if (qualityIssue != null) {
      if (enableDebugMode) print('Face quality insufficient: $qualityIssue');
      return null;
    }

    final bytes = await imageFile.readAsBytes();
    final src = img.decodeImage(bytes);
    if (src == null) {
      if (enableDebugMode) print('Could not decode image');
      return null;
    }

    return await _analyzeCroppedFace(
      src,
      face,
      thrFront,
      thrCrown,
      thrSides,
      enableDebugMode,
    );
  }
}

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
  double numA = 0, numB = 0, den = 0;
  for (var i = 0; i < 3; i++) {
    final sx = c([s1, s2, s3], cs)[i].x;
    final sy = c([s1, s2, s3], cs)[i].y;
    final tx = c([t1, t2, t3], ct)[i].x;
    final ty = c([t1, t2, t3], ct)[i].y;
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

// Canonical keypoints
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
