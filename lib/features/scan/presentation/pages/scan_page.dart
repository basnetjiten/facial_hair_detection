import 'dart:io';
import 'dart:math' as math;
import 'package:face_camera/face_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:whiskrs/features/calibration/presentation/pages/result_page.dart';
import 'package:whiskrs/features/home/presentation/cubit/scan_cubit.dart';

import '../../../../core/di/locator.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  late ScanCubit _scanCubit;
  bool _cameraReady = false;

  @override
  void initState() {
    super.initState();
    _scanCubit = context.read<ScanCubit>();
    _initCamera();
  }

  void _initCamera() {
    cameraService.init(
      onCapture: (File? image) {
        _scanCubit.captureAndAnalyze(image);
      },
      onFaceDetected: (face) {
        _scanCubit.updateCapturedFace(face);
      },
    );
    setState(() => _cameraReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScanCubit, ScanState>(
      bloc: _scanCubit,
      builder: (context, state) {
        return BlocListener<ScanCubit, ScanState>(
          listener: (context, state) {
            if (state.status == ScanStatus.done) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => ResultPage(
                        imagePath: state.imagePath!,
                        result: state.result!,
                      ),
                ),
              );
            } else if (state.status == ScanStatus.error) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.error ?? 'Error')));
            }
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Scan')),
            body:
                _cameraReady
                    ? SmartFaceCamera(
                      indicatorShape: IndicatorShape.circle,
                      indicatorBuilder: (context, face, widgetSize) {
                        if (face == null || face.face?.boundingBox == null) {
                          return const SizedBox.shrink();
                        }

                        final isCentered = face.wellPositioned;
                        final color =
                            isCentered
                                ? Colors.green
                                : Colors.red.withOpacity(0.5);

                        final previewSize = widgetSize;

                        if (previewSize == null) {
                          return const SizedBox.shrink();
                        }

                        return CustomPaint(
                          size: widgetSize!,
                          painter: FaceBoundsPainter(
                            face.face!.boundingBox,
                            color,
                            previewSize, // ✅ pass actual camera preview size here
                          ),
                        );
                      },
                      controller: cameraService.controller!,
                      messageBuilder: (context, face) {
                        if (face == null) {
                          return _message('Place your face in the camera');
                        }
                        if (!face.wellPositioned) {
                          return _message('Center your face in the square');
                        }
                        return const SizedBox.shrink();
                      },
                    )
                    : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }

  Widget _message(String msg) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 55, vertical: 15),
    child: Text(
      msg,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, height: 1.5),
    ),
  );
}

class FaceBoundsPainter extends CustomPainter {
  final Rect boundingBox;
  final Color color;
  final Size previewSize; // camera preview resolution

  FaceBoundsPainter(this.boundingBox, this.color, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    // Maintain aspect ratio
    final scale = math.min(
      size.width / previewSize.width,
      size.height / previewSize.height,
    );

    // Center the preview
    final offsetX = (size.width - previewSize.width * scale) / 2;
    final offsetY = (size.height - previewSize.height * scale) / 2;

    // Scale & offset bounding box
    final scaledBox = Rect.fromLTRB(
      boundingBox.left * scale + offsetX,
      boundingBox.top * scale + offsetY,
      boundingBox.right * scale + offsetX,
      boundingBox.bottom * scale + offsetY,
    );

    // Draw rectangle
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;

    canvas.drawRect(scaledBox, paint);
  }

  @override
  bool shouldRepaint(covariant FaceBoundsPainter oldDelegate) {
    return oldDelegate.boundingBox != boundingBox || oldDelegate.color != color;
  }
}
