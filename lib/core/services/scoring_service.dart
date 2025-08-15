import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:whiskrs/core/services/face_camera_analyzer.dart'
    show FaceCameraRegionAnalyzer;
import 'package:whiskrs/core/services/score_analyzer.dart';
import 'package:whiskrs/features/scan/domain/region.dart';
import 'package:whiskrs/features/scan/domain/scan_result.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class ScoringService {
  /// Enhanced analysis function with better error handling and validation
  Future<ScanResult?> analyze({
    required File imageFile,
    required Face face,
    required double thrFront,
    required double thrCrown,
    required double thrSides,
    double confidenceThreshold = 0.7, // ML Kit face confidence threshold
  }) async {
    // Validate face detection confidence
    if (face.boundingBox.width < 50 || face.boundingBox.height < 50) {
      print('Warning: Face too small for reliable analysis');
      return null;
    }

    final bytes = await imageFile.readAsBytes();
    final src = img.decodeImage(bytes);
    if (src == null) {
      print('Error: Could not decode image');
      return null;
    }

    final start = DateTime.now();

    // Validate face bounding box is within image bounds
    final fb = face.boundingBox;
    if (fb.left < 0 ||
        fb.top < 0 ||
        fb.right > src.width ||
        fb.bottom > src.height) {
      print('Warning: Face bounding box extends outside image bounds');
    }

    return await FaceCameraRegionAnalyzer.analyzeFaceCameraCapture(
      imageFile: imageFile,
      face: face,
      thrFront: thrFront,
      thrCrown: thrCrown,
      thrSides: thrSides,
    );
  }

  /// Utility function to validate landmark quality
  // Map<String, dynamic> validateLandmarkQuality(Face face) {
  //   final landmarks = face.landmarks;
  //   final required = [
  //     FaceLandmarkType.leftEye,
  //     FaceLandmarkType.rightEye,
  //     FaceLandmarkType.noseBase,
  //     FaceLandmarkType.leftMouth,
  //     FaceLandmarkType.rightMouth,
  //     FaceLandmarkType.bottomMouth,
  //   ];
  //
  //   final available = required.where((type) => landmarks.containsKey(type)).length;
  //   final quality = available / required.length;
  //
  //   return {
  //     'quality': quality,
  //     'available_landmarks': available,
  //     'total_required': required.length,
  //     'missing_landmarks': required
  //         .where((type) => !landmarks.containsKey(type))
  //         .map((type) => type.name)
  //         .toList(),
  //     'is_sufficient': quality >= 0.8, // 80% of landmarks should be available
  //   };
  // }

  /// Helper function to visualize regions for debugging
  // List<Map<String, dynamic>> getRegionDebugInfo(Face face, int imageWidth, int imageHeight) {
  //   final regions = androgenicRegions(face);
  //   final fb = face.boundingBox;
  //
  //   return regions.map((region) {
  //     final rx = (fb.left + region.rectNormalized.l * fb.width).round();
  //     final ry = (fb.top + region.rectNormalized.t * fb.height).round();
  //     final rw = ((region.rectNormalized.r - region.rectNormalized.l) * fb.width).round();
  //     final rh = ((region.rectNormalized.b - region.rectNormalized.t) * fb.height).round();
  //
  //     return {
  //       'type': region.type.name,
  //       'normalized': {
  //         'l': region.rectNormalized.l,
  //         't': region.rectNormalized.t,
  //         'r': region.rectNormalized.r,
  //         'b': region.rectNormalized.b,
  //       },
  //       'absolute': {
  //         'x': rx,
  //         'y': ry,
  //         'w': rw,
  //         'h': rh,
  //       },
  //       'valid': rw > 3 && rh > 3 &&
  //           rx >= 0 && ry >= 0 &&
  //           rx + rw <= imageWidth &&
  //           ry + rh <= imageHeight,
  //     };
  //   }).toList();
  // }

  // Future<ScanResult?> analyze({
  //   required File imageFile,
  //   required Face
  //   face, // Exact face from camera_face (pixel-aligned with image)
  //   required double thrFront,
  //   required double thrCrown,
  //   required double thrSides,
  // }) async {
  //   final bytes = await imageFile.readAsBytes();
  //   final src = img.decodeImage(bytes);
  //   if (src == null) return null;
  //
  //   final start = DateTime.now();
  //
  //   final facialRegions = androgenicRegions(face);
  //   final scores = <RegionScore>[];
  //
  //   final fb = face.boundingBox;
  //   final fLeft = fb.left;
  //   final fTop = fb.top;
  //   final fW = fb.width;
  //   final fH = fb.height;
  //
  //   for (final rb in facialRegions) {
  //     final rx = (fLeft + rb.rectNormalized.l * fW).round();
  //     final ry = (fTop + rb.rectNormalized.t * fH).round();
  //     final rw = ((rb.rectNormalized.r - rb.rectNormalized.l) * fW).round();
  //     final rh = ((rb.rectNormalized.b - rb.rectNormalized.t) * fH).round();
  //
  //     if (rw <= 2 || rh <= 2) {
  //       scores.add(RegionScore(rb.type, 0, false));
  //       continue;
  //     }
  //
  //     final s = ImageRegionAnalyzer.scoreRegion(
  //       src: src,
  //       x: rx,
  //       y: ry,
  //       w: rw,
  //       h: rh,
  //     );
  //
  //     final thr = switch (rb.type) {
  //       RegionType.front => thrFront,
  //       RegionType.crown => thrCrown,
  //       RegionType.leftSide => thrSides,
  //       RegionType.rightSide => thrSides,
  //       RegionType.chin => thrSides,
  //       RegionType.upperLip => thrSides,
  //       RegionType.jawline => thrSides,
  //     };
  //
  //     scores.add(RegionScore(rb.type, s, s >= thr));
  //   }
  //
  //   final ms = DateTime.now().difference(start).inMilliseconds;
  //   return ScanResult(scores, ms);
  // }
}
