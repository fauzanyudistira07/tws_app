import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/method_channel_service.dart';

class BluetoothEvent {
  const BluetoothEvent({
    required this.deviceName,
    required this.status,
    required this.timestamp,
    this.batteryLevel,
  });

  final String deviceName;
  final String status;
  final DateTime timestamp;
  final int? batteryLevel;

  factory BluetoothEvent.fromMap(Map<String, dynamic> map) {
    return BluetoothEvent(
      deviceName: (map['deviceName'] as String?)?.trim().isNotEmpty == true
          ? map['deviceName'] as String
          : 'Unknown device',
      status: (map['status'] as String?) ?? 'unknown',
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.now(),
      batteryLevel: map['batteryLevel'] as int?,
    );
  }
}

class BluetoothController extends ChangeNotifier {
  static const String targetKeyword = 'kiip dts16';

  final List<BluetoothEvent> _history = <BluetoothEvent>[];
  final List<DiscoveredTwsDevice> _scanResults = <DiscoveredTwsDevice>[];

  StreamSubscription<Map<String, dynamic>>? _nativeEventSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<OnConnectionStateChangedEvent>? _bleConnectionSubscription;

  bool _serviceRunning = false;
  bool _permissionsReady = false;
  bool _bluetoothSupported = true;
  bool _isScanning = false;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  String? _statusMessage;
  BluetoothEvent? _latestEvent;

  List<BluetoothEvent> get history => List<BluetoothEvent>.unmodifiable(_history);
  List<DiscoveredTwsDevice> get scanResults =>
      List<DiscoveredTwsDevice>.unmodifiable(_scanResults);
  bool get serviceRunning => _serviceRunning;
  bool get permissionsReady => _permissionsReady;
  bool get bluetoothSupported => _bluetoothSupported;
  bool get isScanning => _isScanning;
  BluetoothAdapterState get adapterState => _adapterState;
  String? get statusMessage => _statusMessage;
  BluetoothEvent? get latestEvent => _latestEvent;

  Future<void> initialize() async {
    try {
      _bluetoothSupported = await FlutterBluePlus.isSupported;
      _adapterSubscription ??= FlutterBluePlus.adapterState.listen((state) {
        _adapterState = state;
        notifyListeners();
      });
      _isScanningSubscription ??= FlutterBluePlus.isScanning.listen((value) {
        _isScanning = value;
        notifyListeners();
      });
      _scanSubscription ??= FlutterBluePlus.scanResults.listen(
        _handleScanResults,
        onError: (Object error) {
          _statusMessage = 'Scan error: $error';
          notifyListeners();
        },
      );
      _bleConnectionSubscription ??=
          FlutterBluePlus.events.onConnectionStateChanged.listen(
        _handleBleConnectionState,
      );

      await _ensurePermissions();

      _nativeEventSubscription ??=
          MethodChannelService.connectionEvents().listen(_handleRawEvent);

      final initialEvent = await MethodChannelService.getInitialEvent();
      if (initialEvent != null) {
        await _handleRawEvent(initialEvent);
      }
    } catch (error) {
      _statusMessage = 'Bluetooth initialization failed: $error';
      notifyListeners();
    }
  }

  Future<void> startService() async {
    await _ensurePermissions();
    await MethodChannelService.startBackgroundService();
    _serviceRunning = true;
    notifyListeners();
  }

  Future<void> stopService() async {
    await MethodChannelService.stopBackgroundService();
    _serviceRunning = false;
    notifyListeners();
  }

  Future<void> startScan() async {
    try {
      await _ensurePermissions();
      if (!_bluetoothSupported) {
        _statusMessage = 'Bluetooth LE is not supported on this device.';
        notifyListeners();
        return;
      }
      if (_adapterState != BluetoothAdapterState.on) {
        _statusMessage = 'Turn on Bluetooth first.';
        notifyListeners();
        return;
      }

      _statusMessage = 'Scanning for KiiP DTS16...';
      notifyListeners();
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: false,
      );
    } catch (error) {
      _statusMessage = 'Unable to start scan: $error';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (error) {
      _statusMessage = 'Unable to stop scan: $error';
      notifyListeners();
    }
  }

  Future<void> connectToDevice(DiscoveredTwsDevice item) async {
    try {
      _setBusy(item.remoteId, true);
      _statusMessage = 'Connecting to ${item.displayName}...';
      notifyListeners();

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      await item.device.connect();
      await item.device.discoverServices();

      if (defaultTargetPlatform == TargetPlatform.android) {
        await item.device.createBond().catchError((_) async {});
      }

      _statusMessage = 'Connected to ${item.displayName}.';
      notifyListeners();
    } catch (error) {
      _statusMessage = 'Connection failed: $error';
      notifyListeners();
    } finally {
      _setBusy(item.remoteId, false);
    }
  }

  Future<void> disconnectFromDevice(DiscoveredTwsDevice item) async {
    try {
      _setBusy(item.remoteId, true);
      _statusMessage = 'Disconnecting ${item.displayName}...';
      notifyListeners();
      await item.device.disconnect();
      _statusMessage = 'Disconnected from ${item.displayName}.';
      notifyListeners();
    } catch (error) {
      _statusMessage = 'Disconnect failed: $error';
      notifyListeners();
    } finally {
      _setBusy(item.remoteId, false);
    }
  }

  Future<void> _ensurePermissions() async {
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.notification,
      if (defaultTargetPlatform == TargetPlatform.android)
        Permission.locationWhenInUse,
    ];
    final statuses = await permissions.request();

    final overlayAllowed = await FlutterOverlayWindow.isPermissionGranted() ||
        (await FlutterOverlayWindow.requestPermission() ?? false);

    _permissionsReady =
        statuses.values.every((status) => status.isGranted) && overlayAllowed;
    notifyListeners();
  }

  void _handleScanResults(List<ScanResult> results) {
    final devices = results
        .where((result) => _matchesTarget(result.device.platformName, result.advertisementData.advName))
        .map(
          (result) => DiscoveredTwsDevice(
            device: result.device,
            remoteId: result.device.remoteId.str,
            displayName: _displayNameFor(
              result.device.platformName,
              result.advertisementData.advName,
            ),
            signalStrength: result.rssi,
            connectionState: result.device.isConnected
                ? BluetoothConnectionState.connected
                : BluetoothConnectionState.disconnected,
            isBusy: _findExisting(result.device.remoteId.str)?.isBusy ?? false,
          ),
        )
        .toList()
      ..sort((a, b) => b.signalStrength.compareTo(a.signalStrength));

    _scanResults
      ..clear()
      ..addAll(devices);

    if (_scanResults.isEmpty && !_isScanning) {
      _statusMessage = 'No KiiP DTS16 BLE device found yet.';
    } else if (_scanResults.isNotEmpty) {
      _statusMessage = 'Found ${_scanResults.length} matching device(s).';
    }
    notifyListeners();
  }

  void _handleBleConnectionState(OnConnectionStateChangedEvent event) {
    final remoteId = event.device.remoteId.str;
    final index = _scanResults.indexWhere((item) => item.remoteId == remoteId);
    if (index == -1) {
      return;
    }

    final current = _scanResults[index];
    _scanResults[index] = current.copyWith(
      connectionState: event.connectionState,
      isBusy: false,
    );
    notifyListeners();
  }

  Future<void> _handleRawEvent(Map<String, dynamic> data) async {
    final event = BluetoothEvent.fromMap(data);
    _latestEvent = event;
    _history.insert(0, event);
    if (_history.length > 20) {
      _history.removeLast();
    }

    if (event.status == 'connected' && _permissionsReady) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: false,
        alignment: OverlayAlignment.center,
        height: 340,
        width: 360,
        overlayTitle: 'KiiP DTS16',
        overlayContent: 'Device connected',
        flag: OverlayFlag.defaultFlag,
      );
      await FlutterOverlayWindow.shareData(
        jsonEncode(<String, dynamic>{
          'deviceName': event.deviceName,
          'batteryLevel': event.batteryLevel ?? -1,
          'status': event.status,
        }),
      );
    }

    notifyListeners();
  }

  DiscoveredTwsDevice? _findExisting(String remoteId) {
    for (final item in _scanResults) {
      if (item.remoteId == remoteId) {
        return item;
      }
    }
    return null;
  }

  void _setBusy(String remoteId, bool value) {
    final index = _scanResults.indexWhere((item) => item.remoteId == remoteId);
    if (index == -1) {
      return;
    }
    _scanResults[index] = _scanResults[index].copyWith(isBusy: value);
    notifyListeners();
  }

  bool _matchesTarget(String platformName, String advName) {
    final platform = platformName.toLowerCase();
    final advertised = advName.toLowerCase();
    return platform.contains(targetKeyword) || advertised.contains(targetKeyword);
  }

  String _displayNameFor(String platformName, String advName) {
    final cleanedPlatform = platformName.trim();
    if (cleanedPlatform.isNotEmpty) {
      return cleanedPlatform;
    }
    final cleanedAdv = advName.trim();
    if (cleanedAdv.isNotEmpty) {
      return cleanedAdv;
    }
    return 'KiiP DTS16';
  }

  @override
  void dispose() {
    _nativeEventSubscription?.cancel();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _adapterSubscription?.cancel();
    _bleConnectionSubscription?.cancel();
    super.dispose();
  }
}

class DiscoveredTwsDevice {
  const DiscoveredTwsDevice({
    required this.device,
    required this.remoteId,
    required this.displayName,
    required this.signalStrength,
    required this.connectionState,
    required this.isBusy,
  });

  final BluetoothDevice device;
  final String remoteId;
  final String displayName;
  final int signalStrength;
  final BluetoothConnectionState connectionState;
  final bool isBusy;

  bool get isConnected => connectionState == BluetoothConnectionState.connected;

  DiscoveredTwsDevice copyWith({
    BluetoothConnectionState? connectionState,
    bool? isBusy,
  }) {
    return DiscoveredTwsDevice(
      device: device,
      remoteId: remoteId,
      displayName: displayName,
      signalStrength: signalStrength,
      connectionState: connectionState ?? this.connectionState,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}
