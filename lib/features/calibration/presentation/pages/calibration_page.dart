import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/calibration_cubit.dart';

class CalibrationPage extends StatelessWidget {
  const CalibrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CalibrationCubit(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Calibration')),
        body: BlocBuilder<CalibrationCubit, CalibrationState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sliderTile(
                  label: 'Front threshold',
                  value: state.thrFront,
                  onChanged: (v) => context.read<CalibrationCubit>().setFront(v),
                ),
                _sliderTile(
                  label: 'Crown threshold',
                  value: state.thrCrown,
                  onChanged: (v) => context.read<CalibrationCubit>().setCrown(v),
                ),
                _sliderTile(
                  label: 'Sides threshold',
                  value: state.thrSides,
                  onChanged: (v) => context.read<CalibrationCubit>().setSides(v),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Tip: Higher threshold demands denser texture/darkness to pass.',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sliderTile({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Slider(
          value: value,
          min: 0.05,
          max: 0.9,
          divisions: 35,
          label: value.toStringAsFixed(2),
          onChanged: onChanged,
        ),
        trailing: Text(value.toStringAsFixed(2)),
      ),
    );
  }
}
