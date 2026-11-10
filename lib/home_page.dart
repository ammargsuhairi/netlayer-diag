import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'diagnostic_service.dart';
import 'models.dart';

class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({super.key});

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  final hostC = TextEditingController(text: 'google.com');
  final portC = TextEditingController(text: '443');
  bool running = false;
  bool started = false;
  List<StepResult> steps = DiagnosticService.buildSteps();

  @override
  void dispose() {
    hostC.dispose();
    portC.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    final host = normalizeHost(hostC.text);
    final port = int.tryParse(portC.text.trim()) ?? 443;
    if (host.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Isi host/IP dulu')));
      return;
    }
    setState(() {
      running = true;
      started = true;
      steps = DiagnosticService.buildSteps();
    });
    // Izin lokasi diperlukan Android untuk membaca nama SSID Wi-Fi.
    await Permission.locationWhenInUse.request();
    await DiagnosticService().run(
      host: host,
      port: port,
      steps: steps,
      onChange: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() => running = false);
  }

  String _summaryText() {
    for (final s in steps) {
      if (s.status == StepStatus.fail) {
        return 'Masalah terdeteksi di ${s.layer}: ${s.title}';
      }
    }
    if (steps.any((s) => s.status == StepStatus.warn)) {
      return 'Jaringan jalan, ada peringatan kecil';
    }
    return 'Semua layer normal';
  }

  StepStatus _summaryStatus() {
    if (steps.any((s) => s.status == StepStatus.fail)) return StepStatus.fail;
    if (steps.any((s) => s.status == StepStatus.warn)) return StepStatus.warn;
    return StepStatus.ok;
  }

  String _report() {
    final b = StringBuffer('Laporan NetLayer Diag\n');
    b.writeln('Target: ${hostC.text}:${portC.text}\n');
    for (final s in steps) {
      b.writeln('[${s.status.name.toUpperCase()}] ${s.layer} ${s.title}');
      b.writeln('  ${s.detail}');
      if (s.hint != null) b.writeln('  Saran: ${s.hint}');
    }
    b.writeln('\nKesimpulan: ${_summaryText()}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final done = started && !running;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Diagnosa Jaringan per Layer',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: hostC,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: 'Host / IP', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: TextField(
                controller: portC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Port', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: running ? null : _run,
          icon: running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
          label: Text(running ? 'Memeriksa...' : 'Mulai Diagnosa'),
        ),
        if (done) ...[
          const SizedBox(height: 12),
          _SummaryCard(text: _summaryText(), status: _summaryStatus()),
        ],
        const SizedBox(height: 8),
        for (final s in steps) _StepCard(step: s),
        if (done)
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _report()));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Laporan disalin')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Salin laporan'),
          ),
      ],
    );
  }
}

Color statusColor(StepStatus s) {
  switch (s) {
    case StepStatus.ok:
      return Colors.green;
    case StepStatus.warn:
      return Colors.orange;
    case StepStatus.fail:
      return Colors.red;
    case StepStatus.running:
      return Colors.blue;
    default:
      return Colors.grey;
  }
}

IconData statusIcon(StepStatus s) {
  switch (s) {
    case StepStatus.ok:
      return Icons.check_circle;
    case StepStatus.warn:
      return Icons.warning_amber_rounded;
    case StepStatus.fail:
      return Icons.cancel;
    case StepStatus.skipped:
      return Icons.remove_circle_outline;
    default:
      return Icons.hourglass_empty;
  }
}

class _SummaryCard extends StatelessWidget {
  final String text;
  final StepStatus status;
  const _SummaryCard({required this.text, required this.status});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Card(
      color: c.withOpacity(0.15),
      child: ListTile(
        leading: Icon(statusIcon(status), color: c, size: 32),
        title: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final StepResult step;
  const _StepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(step.status);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            step.status == StepStatus.running
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(statusIcon(step.status), color: c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(step.layer,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: c)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(step.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(step.detail),
                  if (step.hint != null) ...[
                    const SizedBox(height: 4),
                    Text('Saran: ${step.hint}',
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
