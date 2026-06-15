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

  static Future<Map<String, dynamic>?> getInitialEvent() async {
    final event = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
      'getInitialEvent',
    );
    return event?.map((key, value) => MapEntry(key.toString(), value));
  }
}
