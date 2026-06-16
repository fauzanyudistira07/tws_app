import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/bluetooth_controller.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
  });

  final BluetoothController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _historyVisible = false;

  @override
  Widget build(BuildContext context) {
    final latest = widget.controller.latestEvent;
    final history = widget.controller.history;
    final shouldShowRestartCard = widget.controller.restartRequired;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFF8F4EC), Color(0xFFF3F6FA)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            children: <Widget>[
              const _HeaderBlock(),
              if (shouldShowRestartCard) ...<Widget>[
                const SizedBox(height: 16),
                _RestartRequiredCard(controller: widget.controller),
              ],
              const SizedBox(height: 18),
              _MainCard(
                controller: widget.controller,
                latest: latest,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _historyVisible = !_historyVisible;
                  });
                },
                icon: Icon(
                  _historyVisible
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.history_rounded,
                ),
                label: Text(
                  _historyVisible ? 'Hide Connection History' : 'Connection History',
                ),
              ),
              if (_historyVisible) ...<Widget>[
                const SizedBox(height: 14),
                if (history.isEmpty)
                  const _EmptyHistoryCard()
                else
                  ...history.map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _HistoryCard(event: event),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'KiiP DTS16',
          style: TextStyle(
            color: Color(0xFF101828),
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Automatic popup monitor for every new connection.',
          style: TextStyle(
            color: Color(0xFF667085),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _MainCard extends StatelessWidget {
  const _MainCard({
    required this.controller,
    required this.latest,
  });

  final BluetoothController controller;
  final BluetoothEvent? latest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE7ECF2)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              color: const Color(0xFFF5EFE6),
              child: Image.asset(
                'assets/images/kiip_dts16_ui.png',
                width: double.infinity,
                height: 260,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _StatusChip(
                label: controller.serviceRunning ? 'Active' : 'Waiting',
                accent: controller.serviceRunning
                    ? const Color(0xFF12B76A)
                    : const Color(0xFFF79009),
              ),
              const SizedBox(width: 8),
              _StatusChip(
                label: controller.adapterState.name.toUpperCase(),
                accent: const Color(0xFF344054),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Popup card is armed and ready for KiiP DTS16.',
            style: TextStyle(
              color: Color(0xFF101828),
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: controller.showPreviewPopup,
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Preview Popup'),
          ),
          if (latest != null) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: latest!.status == 'connected'
                          ? const Color(0xFFE8F8EF)
                          : const Color(0xFFFDECEC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      latest!.status == 'connected'
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_disabled_rounded,
                      color: latest!.status == 'connected'
                          ? const Color(0xFF12B76A)
                          : const Color(0xFFD92D20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          latest!.deviceName,
                          style: const TextStyle(
                            color: Color(0xFF101828),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          latest!.status == 'connected'
                              ? 'Latest connection detected'
                              : 'Latest disconnect detected',
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    latest!.batteryLevel == null ? '--' : '${latest!.batteryLevel}%',
                    style: const TextStyle(
                      color: Color(0xFF101828),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RestartRequiredCard extends StatelessWidget {
  const _RestartRequiredCard({
    required this.controller,
  });

  final BluetoothController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.restart_alt_rounded,
            color: Color(0xFFB54708),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Open the app again once',
                  style: TextStyle(
                    color: Color(0xFF7A2E0E),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Permission baru selesai. Tutup lalu buka ulang aplikasi agar popup otomatis aktif penuh.',
                  style: TextStyle(
                    color: Color(0xFF9A3412),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: controller.showPreviewPopup,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9A3412),
                    side: const BorderSide(color: Color(0xFFFFD8A8)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Preview Popup'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7ECF2)),
      ),
      child: const Text(
        'No connection history yet.',
        style: TextStyle(
          color: Color(0xFF667085),
          fontSize: 14,
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.event,
  });

  final BluetoothEvent event;

  @override
  Widget build(BuildContext context) {
    final connected = event.status == 'connected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7ECF2)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: connected ? const Color(0xFFE8F8EF) : const Color(0xFFFDECEC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              connected ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: connected ? const Color(0xFF12B76A) : const Color(0xFFD92D20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  event.deviceName,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormat('dd MMM yyyy • HH:mm').format(event.timestamp),
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            connected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              color: connected ? const Color(0xFF12B76A) : const Color(0xFFD92D20),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
