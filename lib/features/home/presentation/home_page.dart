import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:whiskrs/features/calibration/presentation/pages/calibration_page.dart';
import 'package:whiskrs/features/calibration/presentation/pages/result_page.dart';
import 'package:whiskrs/features/home/presentation/cubit/scan_cubit.dart';
import 'package:whiskrs/features/scan/presentation/pages/facial_hair_demo_page.dart';
import 'package:whiskrs/features/scan/presentation/pages/scan_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
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
        appBar: AppBar(title: const Text('Hair Density')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Upload image'),
              subtitle: const Text('Analyze hair density by region'),
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FacialHairDemoPage(),
                    ),
                  ),
              // context.read<ScanCubit>().picImageAndAnalyze(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.camera),
              title: const Text('Start scan'),
              subtitle: const Text('Analyze hair density by region'),
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanPage()),
                  ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Calibration'),
              subtitle: const Text('Set density thresholds per region'),
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CalibrationPage()),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
