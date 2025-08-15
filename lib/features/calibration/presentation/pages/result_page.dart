import 'dart:io';
import 'package:flutter/material.dart';
import 'package:whiskrs/features/scan/domain/region.dart';
import 'package:whiskrs/features/scan/domain/scan_result.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({super.key, required this.imagePath, required this.result});

  final String imagePath;
  final ScanResult result;

  Color _color(RegionScore s) =>
      s.passed
          ? Colors.green
          : s.score >
              (s.passed ? 1.0 : 0.45) // subtle gradient if close
          ? Colors.orange
          : Colors.red;

  String _name(RegionType t) => switch (t) {
    RegionType.front => 'Front',
    RegionType.crown => 'Crown',
    RegionType.leftSide => 'Left Sides',
    RegionType.rightSide => 'Right Sides',
    RegionType.upperLip => 'Upper lip',
    RegionType.chin => 'Chin',
    RegionType.jawline => 'Jawline',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(imagePath)),
          ),
          const SizedBox(height: 16),
          ...result.regionScores.map(
            (s) => Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: _color(s)),
                title: Text('${_name(s.type)}: ${s.score.toStringAsFixed(2)}'),
                subtitle: Text(s.passed ? 'Pass' : 'Below threshold'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Processed in ${result.captureMs} ms'),
        ],
      ),
    );
  }
}
