import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';import '../../../../core/di/locator.dart';

part 'calibration_state.dart';

class CalibrationCubit extends Cubit<CalibrationState> {
  CalibrationCubit()
      : super(CalibrationState(
    thrFront: prefs.thresholdFront,
    thrCrown: prefs.thresholdCrown,
    thrSides: prefs.thresholdSides,
  ));

  Future<void> setFront(double v) async {
    await prefs.setThresholdFront(v);
    emit(state.copyWith(thrFront: v));
  }

  Future<void> setCrown(double v) async {
    await prefs.setThresholdCrown(v);
    emit(state.copyWith(thrCrown: v));
  }

  Future<void> setSides(double v) async {
    await prefs.setThresholdSides(v);
    emit(state.copyWith(thrSides: v));
  }
}
