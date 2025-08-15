part of 'scan_cubit.dart';

enum ScanStatus { idle, capturing, detecting, processing, done, error }

class ScanState extends Equatable {
  const ScanState({
    required this.status,
    this.result,
    this.imagePath,
    this.error,
  });

  const ScanState.initial() : this(status: ScanStatus.idle);

  final ScanStatus status;
  final ScanResult? result;
  final String? imagePath;
  final String? error;

  ScanState copyWith({
    ScanStatus? status,
    ScanResult? result,
    String? imagePath,
    String? error,
  }) =>
      ScanState(
        status: status ?? this.status,
        result: result ?? this.result,
        imagePath: imagePath ?? this.imagePath,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [status, result, imagePath, error];
}
