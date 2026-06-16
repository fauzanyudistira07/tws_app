import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

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
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCFEFF),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x260A1633),
                      blurRadius: 26,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        color: const Color(0xFFF5EFE6),
                        child: Image.asset(
                          'assets/images/kiip_dts16_ui.png',
                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'KiiP DTS16',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF194B8C),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _deviceName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _batteryLevel == null
                          ? 'Connected'
                          : 'Connected • Battery ${_batteryLevel!}%',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF52607A),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          FlutterOverlayWindow.closeOverlay();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'OK',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
