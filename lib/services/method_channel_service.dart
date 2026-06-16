import 'dart:async';

import 'package:flutter/services.dart';

class MethodChannelService {
  MethodChannelService._();

  static const MethodChannel _methodChannel = MethodChannel('apk_tws/service');
  static const EventChannel _eventChannel = EventChannel('apk_tws/events');

  static Stream<Map<String, dynamic>>? _events;

  static Stream<Map<String, dynamic>> connectionEvents() {
    _events ??= _eventChannel.receiveBroadcastStream().map((dynamic event) {
      final map = Map<dynamic, dynamic>.from(event as Map);
      return map.map((key, value) => MapEntry(key.toString(), value));
    });
    return _events!;
  }

  static Future<void> startBackgroundService() {
    return _methodChannel.invokeMethod<void>('startService');
  }

  static Future<void> stopBackgroundService() {
    return _methodChannel.invokeMethod<void>('stopService');
  }

  static Future<bool> isServiceRunning() async {
    return await _methodChannel.invokeMethod<bool>('isServiceRunning') ?? false;
  }

  static Future<bool> hasOverlayPermission() async {
    return await _methodChannel.invokeMethod<bool>('hasOverlayPermission') ??
        false;
  }

  static Future<Map<String, dynamic>?> getInitialEvent() async {
    final event = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
      'getInitialEvent',
    );
    return event?.map((key, value) => MapEntry(key.toString(), value));
  }

  static Future<List<Map<String, dynamic>>> getEventHistory() async {
    final events = await _methodChannel.invokeMethod<List<dynamic>>(
      'getEventHistory',
    );
    if (events == null) {
      return const <Map<String, dynamic>>[];
    }

    return events
        .map((dynamic event) => Map<dynamic, dynamic>.from(event as Map))
        .map(
          (map) => map.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  static Future<void> showPreviewPopup() {
    return _methodChannel.invokeMethod<void>('showPreviewPopup');
  }
}
