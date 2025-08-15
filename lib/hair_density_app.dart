import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:whiskrs/features/home/presentation/cubit/scan_cubit.dart';
import 'package:whiskrs/features/home/presentation/home_page.dart';
import 'core/di/locator.dart';
import 'theme/app_theme.dart';

class HairDensityApp extends StatefulWidget {
  const HairDensityApp({super.key});

  @override
  State<HairDensityApp> createState() => _HairDensityAppState();
}

class _HairDensityAppState extends State<HairDensityApp> {
  @override
  void initState() {
    super.initState();
    setupLocator();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [BlocProvider(create: (context) => ScanCubit())],
      child: MaterialApp(
        title: 'Hair Density',
        theme: AppTheme.light,
        home: const HomePage(),
      ),
    );
  }
}
