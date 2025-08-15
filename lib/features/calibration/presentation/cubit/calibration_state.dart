part of 'calibration_cubit.dart';

class CalibrationState extends Equatable {
  const CalibrationState({
    required this.thrFront,
    required this.thrCrown,
    required this.thrSides,
  });

  final double thrFront;
  final double thrCrown;
  final double thrSides;

  CalibrationState copyWith({
    double? thrFront,
    double? thrCrown,
    double? thrSides,
  }) =>
      CalibrationState(
        thrFront: thrFront ?? this.thrFront,
        thrCrown: thrCrown ?? this.thrCrown,
        thrSides: thrSides ?? this.thrSides,
      );

  @override
  List<Object?> get props => [thrFront, thrCrown, thrSides];
}
