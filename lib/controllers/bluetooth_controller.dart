import 'dart:async';

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
  bool _restartRequired = false;
  bool _overlayPermissionGranted = false;
  bool _bluetoothPermissionGranted = false;
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
  bool get restartRequired => _restartRequired;
  BluetoothAdapterState get adapterState => _adapterState;
  String? get statusMessage => _statusMessage;
  BluetoothEvent? get latestEvent => _latestEvent;

  Future<void> initialize() async {
    try {
      await _captureInitialPermissionSnapshot();
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
      await _ensureBackgroundService();
      _serviceRunning = await MethodChannelService.isServiceRunning();

      final storedHistory = await MethodChannelService.getEventHistory();
      _restoreHistory(storedHistory);

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
    _statusMessage = 'Background popup service is running.';
    notifyListeners();
  }

  Future<void> stopService() async {
    await MethodChannelService.stopBackgroundService();
    _serviceRunning = false;
    _statusMessage = 'Background popup service stopped.';
    notifyListeners();
  }

  Future<void> showPreviewPopup() async {
    try {
      await _ensurePermissions();
      await MethodChannelService.showPreviewPopup();
      _statusMessage = 'Showing preview popup...';
      notifyListeners();
    } catch (error) {
      _statusMessage = 'Preview popup failed: $error';
      notifyListeners();
    }
  }

  Future<void> _ensureBackgroundService() async {
    if (!_permissionsReady) {
      return;
    }

    try {
      if (!await MethodChannelService.isServiceRunning()) {
        await MethodChannelService.startBackgroundService();
      }
      _serviceRunning = await MethodChannelService.isServiceRunning();
      _statusMessage = 'Background popup service is running.';
      notifyListeners();
    } catch (error) {
      _serviceRunning = false;
      _statusMessage = 'Unable to start background service: $error';
      notifyListeners();
    }
  }

  Future<void> refreshAfterResume() async {
    await _ensurePermissions();
    _serviceRunning = await MethodChannelService.isServiceRunning();
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
    final wasBluetoothGranted = _bluetoothPermissionGranted;
    final wasOverlayGranted = _overlayPermissionGranted;

    final permissions = <Permission>[
      Permission.bluetoothConnect,
      if (defaultTargetPlatform == TargetPlatform.android)
        Permission.notification,
    ];
    final statuses = await permissions.request();

    var overlayAllowed = await MethodChannelService.hasOverlayPermission();
    if (!overlayAllowed) {
      overlayAllowed = await FlutterOverlayWindow.isPermissionGranted() ||
          (await FlutterOverlayWindow.requestPermission() ?? false);
      if (!overlayAllowed) {
        overlayAllowed = await MethodChannelService.hasOverlayPermission();
      }
    }

    final bluetoothReady =
        statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final notificationReady = defaultTargetPlatform != TargetPlatform.android ||
        (statuses[Permission.notification]?.isGranted ?? true);

    _bluetoothPermissionGranted = bluetoothReady;
    _overlayPermissionGranted = overlayAllowed;
    _permissionsReady = bluetoothReady;
    if ((bluetoothReady && !wasBluetoothGranted) ||
        (overlayAllowed && !wasOverlayGranted)) {
      _restartRequired = true;
    }
    if (_permissionsReady) {
      await _ensureBackgroundService();
      _serviceRunning = await MethodChannelService.isServiceRunning();
      if (!notificationReady) {
        _statusMessage = 'Popup monitor aktif, tapi notifikasi Android belum diizinkan.';
      } else if (!overlayAllowed) {
        _statusMessage = 'Bluetooth monitor aktif, tapi izin tampil di atas aplikasi belum aktif.';
      }
    } else {
      _serviceRunning = false;
    }
    notifyListeners();
  }

  Future<void> _captureInitialPermissionSnapshot() async {
    _bluetoothPermissionGranted =
        (await Permission.bluetoothConnect.status).isGranted;
    _overlayPermissionGranted = await MethodChannelService.hasOverlayPermission();
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
    _insertEvent(event);

    notifyListeners();
  }

  void _restoreHistory(List<Map<String, dynamic>> events) {
    _history
      ..clear()
      ..addAll(events.map(BluetoothEvent.fromMap));

    if (_history.isNotEmpty) {
      _latestEvent = _history.first;
    }
    notifyListeners();
  }

  void _insertEvent(BluetoothEvent event) {
    final duplicated = _history.any(
      (existing) =>
          existing.deviceName == event.deviceName &&
          existing.status == event.status &&
          existing.timestamp == event.timestamp,
    );
    if (duplicated) {
      _latestEvent = event;
      return;
    }

    _latestEvent = event;
    _history.insert(0, event);
    if (_history.length > 20) {
      _history.removeLast();
    }
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
