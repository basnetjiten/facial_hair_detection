import 'package:face_camera/face_camera.dart';
import 'package:flutter/material.dart';
import 'package:whiskrs/hair_density_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FaceCamera.initialize();
  runApp(const HairDensityApp());
}
