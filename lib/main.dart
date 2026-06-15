import 'package:flutter/material.dart';

import 'controllers/bluetooth_controller.dart';
import 'views/popup_overlay_widget.dart';
import 'views/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: PopupOverlayWidget(),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final BluetoothController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BluetoothController()
      ..addListener(_refresh)
      ..initialize();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KiiP DTS16 Connect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF194B8C)),
        useMaterial3: true,
      ),
      home: DashboardScreen(controller: _controller),
    );
  }
}
