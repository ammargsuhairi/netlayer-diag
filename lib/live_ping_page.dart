import 'dart:async';

import 'package:dart_ping/dart_ping.dart';
import 'package:flutter/material.dart';

import 'diagnostic_service.dart';

class LivePingPage extends StatefulWidget {
  const LivePingPage({super.key});

  @override
  State<LivePingPage> createState() => _LivePingPageState();
}

class _LivePingPageState extends State<LivePingPage> {
  final hostC = TextEditingController(text: '8.8.8.8');
  Ping? _ping;
  StreamSubscription<PingData>? _sub;
  bool running = false;
  int sent = 0, received = 0;
  final List<int> rtts = [];
  final List<_Line> lines = [];

  @override
  void dispose() {
    _stop();
    hostC.dispose();
    super.dispose();
  }

  void _start() {
    final host = normalizeHost(hostC.text);
    if (host.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      running = true;
      sent = 0;
      received = 0;
      rtts.clear();
      lines.clear();
    });
    _ping = Ping(host, timeout: 2);
    _sub = _ping!.stream.listen((e) {
      if (!mounted) return;
      setState(() {
        if (e.response != null) {
          final r = e.response!;
          sent++;
          received++;
          final ms = r.time?.inMilliseconds;
          if (ms != null) rtts.add(ms);
          lines.insert(
              0,
              _Line(
                  'Balasan dari ${r.ip}: seq=${r.seq} ttl=${r.ttl} waktu=${ms ?? '?'} ms',
                  false));
        } else if (e.error != null) {
          sent++;
          lines.insert(0, _Line(pingErrorText(e.error!.error), true));
        }
        if (lines.length > 200) lines.removeLast();
      });
    }, onDone: () {
      if (mounted) setState(() => running = false);
    });
  }

  void _stop() {
    _ping?.stop();
    _sub?.cancel();
    _ping = null;
    _sub = null;
    if (mounted && running) setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    final loss = sent == 0 ? 0 : (sent - received) * 100 / sent;
    final min = rtts.isEmpty ? null : rtts.reduce((a, b) => a < b ? a : b);
    final max = rtts.isEmpty ? null : rtts.reduce((a, b) => a > b ? a : b);
    final avg =
        rtts.isEmpty ? null : (rtts.reduce((a, b) => a + b) / rtts.length).round();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: hostC,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'Host / IP', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: running ? _stop : _start,
                child: Text(running ? 'Stop' : 'Ping'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('Kirim', '$sent'),
                  _stat('Terima', '$received'),
                  _stat('Loss', '${loss.toStringAsFixed(0)}%'),
                  _stat('Min', min == null ? '-' : '$min ms'),
                  _stat('Avg', avg == null ? '-' : '$avg ms'),
                  _stat('Max', max == null ? '-' : '$max ms'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: lines.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  lines[i].text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: lines[i].error ? Colors.red : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _Line {
  final String text;
  final bool error;
  _Line(this.text, this.error);
}
