import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  Prefs(this._sp);
  final SharedPreferences _sp;

  static const _tFront = 'threshold_front';
  static const _tCrown = 'threshold_crown';
  static const _tSides = 'threshold_sides';

  double get thresholdFront => _sp.getDouble(_tFront) ?? 0.15;
  double get thresholdCrown => _sp.getDouble(_tCrown) ?? 0.15;
  double get thresholdSides => _sp.getDouble(_tSides) ?? 0.15;

  Future<void> setThresholdFront(double v) => _sp.setDouble(_tFront, v);
  Future<void> setThresholdCrown(double v) => _sp.setDouble(_tCrown, v);
  Future<void> setThresholdSides(double v) => _sp.setDouble(_tSides, v);
}
