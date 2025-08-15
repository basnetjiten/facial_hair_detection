import 'package:flutter/material.dart';
import 'package:whiskrs/features/calibration/presentation/pages/calibration_page.dart';
import 'package:whiskrs/features/scan/presentation/pages/scan_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hair Density')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.camera),
            title: const Text('Start scan'),
            subtitle: const Text('Analyze hair density by region'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScanPage()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Calibration'),
            subtitle: const Text('Set density thresholds per region'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CalibrationPage()),
            ),
          ),
        ],
      ),
    );
  }
}
