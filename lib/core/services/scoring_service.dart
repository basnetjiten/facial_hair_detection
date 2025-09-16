import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:whiskrs/core/services/face_camera_analyzer.dart'
    show FaceCameraRegionAnalyzer;

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
}
