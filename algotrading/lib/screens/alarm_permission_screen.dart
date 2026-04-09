import 'dart:io';
import 'package:flutter/material.dart';
import '../services/alarm_permission_service.dart';

/// Full-screen setup wizard that walks the user through granting the three
/// Android permissions required for the trade alarm to wake the screen.
///
/// Show this once after first login, or any time a permission is missing.
class AlarmPermissionScreen extends StatefulWidget {
  /// If true the screen was opened manually from settings — show a back button.
  final bool fromSettings;

  const AlarmPermissionScreen({super.key, this.fromSettings = false});

  @override
  State<AlarmPermissionScreen> createState() => _AlarmPermissionScreenState();
}

class _AlarmPermissionScreenState extends State<AlarmPermissionScreen> {
  static const _pkg = 'com.vantrade.app';

  AlarmPermissionStatus? _status;
  bool _checking = false;

  final _svc = AlarmPermissionService.instance;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!Platform.isAndroid) {
      setState(() => _status = const AlarmPermissionStatus(
            notifications: true,
            exactAlarm: true,
          ));
      return;
    }
    setState(() => _checking = true);
    final s = await _svc.checkAll();
    if (mounted) setState(() { _status = s; _checking = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: const Text('Alarm Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        automaticallyImplyLeading: widget.fromSettings,
        actions: [
          if (_status?.allGranted == true)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _checking || _status == null
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = _status!;
    final allDone = s.allGranted;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: allDone ? Colors.green[900] : Colors.orange[900],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                allDone ? Icons.check_circle : Icons.alarm_on,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allDone ? 'Alarm is ready!' : 'Set up Trade Alarm',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      allDone
                          ? 'VanTrade will wake your screen when a trade opportunity is found.'
                          : 'Complete the steps below so the alarm wakes your screen even when it\'s locked.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Step 1 — Notifications
        _PermissionTile(
          step: 1,
          title: 'Allow Notifications',
          subtitle: 'Required to show the alarm notification at all.',
          granted: s.notifications,
          actionLabel: s.notifications ? 'Granted' : 'Grant Permission',
          onTap: s.notifications
              ? null
              : () async {
                  await _svc.requestNotificationPermission();
                  await _refresh();
                },
          note: s.notifications
              ? null
              : 'Tap Grant Permission — an OS dialog will appear.',
        ),

        const SizedBox(height: 12),

        // Step 2 — Exact alarm / Alarms & reminders
        _PermissionTile(
          step: 2,
          title: 'Alarms & Reminders',
          subtitle: 'Lets the alarm fire at the exact scheduled time, even in battery-saver / Doze mode.',
          granted: s.exactAlarm,
          actionLabel: s.exactAlarm ? 'Granted' : 'Open Settings',
          onTap: s.exactAlarm
              ? null
              : () async {
                  await _svc.openExactAlarmSettings(_pkg);
                  // Re-check after returning from settings
                  await Future.delayed(const Duration(seconds: 1));
                  await _refresh();
                },
          note: s.exactAlarm
              ? null
              : 'Settings → Apps → Special app access → Alarms & reminders → VanTrade → Allow.',
        ),

        const SizedBox(height: 12),

        // Step 3 — Full-screen intent (no runtime check API — manual confirmation)
        _PermissionTile(
          step: 3,
          title: 'Full-Screen Notifications',
          subtitle: 'Wakes the screen and shows the alarm over the lock screen.',
          granted: s.fullScreenIntent,
          actionLabel: s.fullScreenIntent ? 'Confirmed' : 'Open Settings',
          onTap: s.fullScreenIntent ? null : () async {
            await _svc.openFullScreenIntentSettings(_pkg);
          },
          note: s.fullScreenIntent ? null :
              'Settings → Apps → VanTrade → Notifications\n'
              '→ Enable "Allow full-screen notifications"\n\n'
              'After enabling, tap "I\'ve enabled it" below.',
          confirmButton: s.fullScreenIntent ? null : _ConfirmFsiButton(
            onConfirmed: () async {
              await _svc.markFullScreenIntentConfirmed();
              await _refresh();
            },
          ),
        ),

        const SizedBox(height: 28),

        // Refresh button
        OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Re-check permissions'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        if (allDone) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check),
            label: const Text('All set — continue to app', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final int step;
  final String title;
  final String subtitle;
  final bool granted;
  final String actionLabel;
  final VoidCallback? onTap;
  final String? note;
  final Widget? confirmButton;

  const _PermissionTile({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.actionLabel,
    required this.onTap,
    this.note,
    this.confirmButton,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = granted;
    final accent = isDone ? Colors.greenAccent : Colors.orange[400]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDone ? Colors.green[800]! : Colors.orange[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Step badge
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? Colors.green[700] : Colors.orange[800],
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text('$step', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(note!,
                  style: TextStyle(color: Colors.grey[300], fontSize: 12, height: 1.5)),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: isDone
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: Text(actionLabel),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green[400],
                      side: BorderSide(color: Colors.green[800]!),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.settings, size: 16),
                    label: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
          ),
          if (confirmButton != null) ...[
            const SizedBox(height: 8),
            confirmButton!,
          ],
        ],
      ),
    );
  }
}

class _ConfirmFsiButton extends StatelessWidget {
  final VoidCallback onConfirmed;
  const _ConfirmFsiButton({required this.onConfirmed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onConfirmed,
        icon: const Icon(Icons.check_circle_outline, size: 16),
        label: const Text("I've enabled it", style: TextStyle(fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.greenAccent,
          side: const BorderSide(color: Colors.green),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
