import 'dart:io';
import 'package:face_camera/face_camera.dart';

class CameraService {
  FaceCameraController? controller;

  /// Initialize the controller with auto-capture and callbacks
  Future<FaceCameraController> init({
    required void Function(File? image) onCapture,
    void Function(Face? face)? onFaceDetected,
  }) async {
    controller = FaceCameraController(
      performanceMode: FaceDetectorMode.accurate,
      enableAudio: false,
      autoCapture: true,
      defaultCameraLens: CameraLens.front,
      onCapture: onCapture,
      onFaceDetected: onFaceDetected,
    );

    return controller!;
  }

  /// Start stream again after capture if needed
  Future<void> restartCameraStream() async {
    await controller!.startImageStream();
  }
}
