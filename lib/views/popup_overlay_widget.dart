import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:lottie/lottie.dart';

class PopupOverlayWidget extends StatefulWidget {
  const PopupOverlayWidget({super.key});

  @override
  State<PopupOverlayWidget> createState() => _PopupOverlayWidgetState();
}

class _PopupOverlayWidgetState extends State<PopupOverlayWidget> {
  String _deviceName = 'KiiP DTS16';
  int? _batteryLevel;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((dynamic data) {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceName = (decoded['deviceName'] as String?) ?? _deviceName;
        final battery = decoded['batteryLevel'] as int?;
        _batteryLevel = battery != null && battery >= 0 ? battery : null;
      });
    });
    Future<void>.delayed(
      const Duration(seconds: 4),
      FlutterOverlayWindow.closeOverlay,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFFFCFCFF), Color(0xFFE5ECF8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x330A1633),
                blurRadius: 24,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 110,
                child: Lottie.asset(
                  'assets/animations/tws_popup_anim.json',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _deviceName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _batteryLevel == null
                    ? 'Connected'
                    : 'Battery level ${_batteryLevel!}%',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF52607A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
