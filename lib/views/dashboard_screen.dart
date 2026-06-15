import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';

import '../controllers/bluetooth_controller.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
  });

  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    final latest = controller.latestEvent;
    final history = controller.history;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('KiiP DTS16 Monitor'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _StatusCard(controller: controller, latest: latest),
          const SizedBox(height: 20),
          _ScanSection(controller: controller),
          const SizedBox(height: 20),
          Text(
            'Connection History',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            const _EmptyState()
          else
            ...history.map(
              (event) => Card(
                child: ListTile(
                  leading: Icon(
                    event.status == 'connected'
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                  ),
                  title: Text(event.deviceName),
                  subtitle: Text(
                    DateFormat('dd MMM yyyy, HH:mm').format(event.timestamp),
                  ),
                  trailing: Text(
                    event.batteryLevel == null
                        ? event.status
                        : '${event.batteryLevel}%',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.controller,
    required this.latest,
  });

  final BluetoothController controller;
  final BluetoothEvent? latest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF10213F), Color(0xFF194B8C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Background Service',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            controller.serviceRunning ? 'Running' : 'Stopped',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            controller.permissionsReady
                ? 'Bluetooth and overlay permissions granted.'
                : 'Grant Bluetooth, notification, and overlay permissions.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            'Adapter: ${controller.adapterState.name}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            controller.bluetoothSupported
                ? 'BLE supported by this phone.'
                : 'BLE is not supported by this phone.',
            style: const TextStyle(color: Colors.white70),
          ),
          if (controller.statusMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              controller.statusMessage!,
              style: const TextStyle(color: Colors.white),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              ElevatedButton(
                onPressed: controller.startService,
                child: const Text('Start'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: controller.stopService,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                ),
                child: const Text('Stop'),
              ),
            ],
          ),
          if (latest != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Last event: ${latest!.deviceName} ${latest!.status}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanSection extends StatelessWidget {
  const _ScanSection({
    required this.controller,
  });

  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    final results = controller.scanResults;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'BLE Device Scan',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
              ),
            ),
            FilledButton.icon(
              onPressed: controller.isScanning
                  ? controller.stopScan
                  : controller.startScan,
              icon: Icon(
                controller.isScanning ? Icons.stop_circle : Icons.search,
              ),
              label: Text(controller.isScanning ? 'Stop' : 'Scan'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: results.isEmpty
              ? const Text(
                  'Scan untuk mencari KiiP DTS16 yang mengiklankan BLE. Jika TWS ini hanya Bluetooth audio klasik, device tidak akan muncul di daftar ini.',
                )
              : Column(
                  children: results
                      .map(
                        (item) => _DeviceTile(
                          controller: controller,
                          item: item,
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.controller,
    required this.item,
  });

  final BluetoothController controller;
  final DiscoveredTwsDevice item;

  @override
  Widget build(BuildContext context) {
    final isConnected = item.isConnected;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: isConnected
            ? const Color(0xFFD7F5E8)
            : const Color(0xFFE6EEF9),
        child: Icon(
          isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
          color: const Color(0xFF194B8C),
        ),
      ),
      title: Text(item.displayName),
      subtitle: Text(
        '${item.remoteId}\nRSSI ${item.signalStrength} dBm · ${_connectionLabel(item.connectionState)}',
      ),
      isThreeLine: true,
      trailing: item.isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton(
              onPressed: isConnected
                  ? () => controller.disconnectFromDevice(item)
                  : () => controller.connectToDevice(item),
              child: Text(isConnected ? 'Disconnect' : 'Connect'),
            ),
    );
  }

  String _connectionLabel(BluetoothConnectionState state) {
    return state == BluetoothConnectionState.connected
        ? 'connected'
        : 'disconnected';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text('No Bluetooth connection history yet.'),
    );
  }
}
