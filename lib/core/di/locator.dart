import 'package:shared_preferences/shared_preferences.dart';
import 'package:whiskrs/core/services/camera_service.dart';
import 'package:whiskrs/core/services/scoring_service.dart';
import '../persistence/prefs.dart';

late Prefs prefs;
late CameraService cameraService;
late ScoringService scoringService;

Future<void> setupLocator() async {
  final sp = await SharedPreferences.getInstance();
  prefs = Prefs(sp);
  cameraService = CameraService();
  scoringService = ScoringService();
}
