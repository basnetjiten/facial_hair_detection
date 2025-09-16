import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:face_camera/face_camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:whiskrs/features/scan/domain/scan_result.dart';
import '../../../../core/di/locator.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart' as p;
import 'package:image_picker/image_picker.dart';

part 'scan_state.dart';

class ScanCubit extends Cubit<ScanState> {
  ScanCubit() : super(const ScanState.initial());

  Face? _face;

  Future<File> fileFromAsset(String assetPath, String filename) async {
    final byteData = await rootBundle.load(assetPath);

    final tempDir = await p.getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');

    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  Future<void> captureAndAnalyze(File? file) async {
    emit(state.copyWith(status: ScanStatus.capturing));

    if (file == null) {
      emit(
        state.copyWith(status: ScanStatus.error, error: 'No images detected'),
      );
      return;
    }
    try {
      emit(state.copyWith(status: ScanStatus.detecting));

      final scanResult = await scoringService.analyze(
        imageFile: file,
        face: _face!,
        thrFront: prefs.thresholdFront,
        thrCrown: prefs.thresholdCrown,
        thrSides: prefs.thresholdSides,
      );

      if (scanResult == null) {
        emit(
          state.copyWith(status: ScanStatus.error, error: 'Processing failed'),
        );
        return;
      }
      emit(
        state.copyWith(
          status: ScanStatus.done,
          result: scanResult,
          imagePath: file.path,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: ScanStatus.error, error: e.toString()));
    }
  }

  void updateCapturedFace(Face? face) {
    _face = face;
  }

  Future<File?> _pickImage() async {
    try {
      final XFile? pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        return File(pickedFile.path);
      }
      return null;
    } catch (e) {
      emit(
        state.copyWith(
          status: ScanStatus.error,
          error: 'Failed to pick image: ${e.toString()}',
        ),
      );
      return null;
    }
  }

  Future<void> picImageAndAnalyze() async {
    emit(state.copyWith(status: ScanStatus.capturing));

    try {
      // If no file is provided, pick one from gallery
      File? file = await _pickImage();

      if (file == null) {
        emit(
          state.copyWith(status: ScanStatus.error, error: 'No image selected'),
        );
        return;
      }

      FaceDetector faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
        ),
      );
      final List<Face> faces = await faceDetector.processImage(
        InputImage.fromFile(file),
      );
      _face = faces.first;

      try {
        emit(state.copyWith(status: ScanStatus.detecting));

        final scanResult = await scoringService.analyze(
          imageFile: file,
          face: _face!,
          thrFront: prefs.thresholdFront,
          thrCrown: prefs.thresholdCrown,
          thrSides: prefs.thresholdSides,
        );

        if (scanResult == null) {
          emit(
            state.copyWith(
              status: ScanStatus.error,
              error: 'Processing failed',
            ),
          );
          return;
        }
        emit(
          state.copyWith(
            status: ScanStatus.done,
            result: scanResult,
            imagePath: file.path,
          ),
        );
      } catch (e) {
        emit(state.copyWith(status: ScanStatus.error, error: e.toString()));
      }
    } catch (e) {
      emit(
        state.copyWith(status: ScanStatus.error, error: 'No faces detected'),
      );
    }
  }
}
