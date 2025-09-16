import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:whiskrs/features/scan/presentation/widgets/facial_hair_painter.dart';

class FacialHairDemoPage extends StatefulWidget {
  const FacialHairDemoPage({super.key});

  @override
  State<FacialHairDemoPage> createState() => _FacialHairDemoPageState();
}

class _FacialHairDemoPageState extends State<FacialHairDemoPage> {
  ui.Image? _faceImage;

  final facialHairData = {
    "facialHair": {
      "hasBeard": false,
      "hasMustache": true,
      "hasChinHair": false,
      "hasJawlineHair": false,
      "hasSideburnHair": false,
      "hasNeckHair": false,
      "hasCheekHair": false,
      "density": "low",
      "contours": [
        {"x": 100, "y": 150, "type": "mustache"},
        {"x": 110, "y": 160, "type": "mustache"},
        {"x": 120, "y": 170, "type": "mustache"},
        {"x": 130, "y": 165, "type": "mustache"},
        {"x": 140, "y": 160, "type": "mustache"},
        {"x": 150, "y": 150, "type": "mustache"},
        {"x": 130, "y": 155, "type": "mustache"},
        {"x": 120, "y": 160, "type": "mustache"},
      ],
    },
    "confidence": 0.8,
  };

  @override
  void initState() {
    super.initState();
    _loadFaceImage();
  }

  Future<void> _loadFaceImage() async {
    final img = await loadImage('assets/images/face.jpg');
    setState(() {
      _faceImage = img;
    });
  }

  Future<ui.Image> loadImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Facial Hair Demo')),
      body: Center(
        child:
            _faceImage == null
                ? const CircularProgressIndicator()
                : Container(
                  width: 300,
                  height: 400,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/images/face.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                      CustomPaint(
                        painter: FacialHairPainter(
                          facialHairData: facialHairData,
                          imageSize: Size(
                            _faceImage!.width.toDouble(),
                            _faceImage!.height.toDouble(),
                          ),
                          hairColor: Colors.brown[800]!,
                          strokeWidth: 3.0,
                          opacity: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}
