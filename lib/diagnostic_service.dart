import 'dart:async';
import 'dart:io';
import 'dart:ui' show VoidCallback;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dart_ping/dart_ping.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'models.dart';

String pingErrorText(ErrorType t) {
  switch (t.name) {
    case 'requestTimedOut':
      return 'Request timed out (L3: paket tidak dibalas)';
    case 'unknownHost':
      return 'Unknown host (nama domain gagal di-resolve, DNS)';
    case 'unreachable':
      return 'Destination host unreachable (tidak ada route, L3)';
    case 'noReply':
      return 'No reply (L3: tidak ada balasan)';
    default:
      return 'Error ping tidak dikenal';
  }
}

class PingStats {
  int sent = 0;
  int received = 0;
  final List<int> rtts = [];
  String? error;

  bool get ok => received > 0;
  double get loss => sent == 0 ? 100 : (sent - received) * 100 / sent;
  int? get avg =>
      rtts.isEmpty ? null : (rtts.reduce((a, b) => a + b) / rtts.length).round();

  String describe() {
    if (ok) {
      return '$received/$sent balasan, loss ${loss.toStringAsFixed(0)}%, rata-rata ${avg ?? '?'} ms';
    }
    return error ?? 'Tidak ada balasan';
  }
}

Future<PingStats> pingHost(String host, {int count = 3}) async {
  final stats = PingStats();
  try {
    final ping = Ping(host, count: count, timeout: 2);
    final timer = Timer(Duration(seconds: count * 3 + 4), () => ping.stop());
    bool gotSummary = false;
    await for (final e in ping.stream) {
      if (e.response != null) {
        stats.received++;
        final t = e.response!.time;
        if (t != null) stats.rtts.add(t.inMilliseconds);
      }
      if (e.error != null) stats.error = pingErrorText(e.error!.error);
      if (e.summary != null) {
        gotSummary = true;
        stats.sent = e.summary!.transmitted;
        stats.received = e.summary!.received;
      }
    }
    timer.cancel();
    if (!gotSummary) stats.sent = count;
  } catch (e) {
    stats.sent = count;
    stats.error = 'Gagal menjalankan ping: $e';
  }
  return stats;
}

String describeSocketError(Object e) {
  if (e is TimeoutException) return 'Timeout (tidak ada respons)';
  if (e is HandshakeException) return 'TLS handshake gagal: ${e.message}';
  if (e is TlsException) return 'Error TLS: ${e.message}';
  if (e is SocketException) {
    final code = e.osError?.errorCode;
    final msg = e.message.toLowerCase();
    if (code == 111) return 'Connection refused (port tertutup atau layanan mati)';
    if (code == 113) return 'No route to host (tidak ada jalur ke host)';
    if (code == 101) return 'Network is unreachable (tidak ada route)';
    if (code == 110 || msg.contains('timed out')) {
      return 'Connection timed out (kemungkinan diblokir firewall)';
    }
    if (msg.contains('failed host lookup')) return 'Gagal resolve nama host (DNS)';
    return 'SocketException: ${e.message} ${e.osError?.message ?? ''}'.trim();
  }
  return e.toString();
}

bool isIp(String s) => InternetAddress.tryParse(s) != null;

String normalizeHost(String input) {
  var s = input.trim();
  if (s.isEmpty) return '';
  if (s.contains('://')) {
    s = Uri.tryParse(s)?.host ?? s;
  }
  s = s.split('/').first;
  if (!s.contains(':') || s.split(':').length == 2) {
    s = s.split(':').first;
  }
  return s;
}

class DiagnosticService {
  static List<StepResult> buildSteps() => [
        StepResult(layer: 'L1-L2', title: 'Koneksi fisik/link'),
        StepResult(layer: 'L2-L3', title: 'Gateway lokal'),
        StepResult(layer: 'L3', title: 'Internet (IP publik)'),
        StepResult(layer: 'DNS', title: 'Resolusi nama domain'),
        StepResult(layer: 'L3', title: 'Ping ke target'),
        StepResult(layer: 'L4', title: 'Koneksi TCP ke port'),
        StepResult(layer: 'L5-L6', title: 'TLS/SSL handshake'),
        StepResult(layer: 'L7', title: 'Respons HTTP/HTTPS'),
      ];

  Future<void> run({
    required String host,
    required int port,
    required List<StepResult> steps,
    required VoidCallback onChange,
  }) async {
    void set(int i, StepStatus s, String detail, [String? hint]) {
      steps[i]
        ..status = s
        ..detail = detail
        ..hint = hint;
      onChange();
    }

    void start(int i) => set(i, StepStatus.running, 'Memeriksa...');

    void skipFrom(int i, String why) {
      for (var k = i; k < steps.length; k++) {
        if (steps[k].status == StepStatus.pending) {
          set(k, StepStatus.skipped, why);
        }
      }
    }

    // 0: Link
    start(0);
    final conn = await Connectivity().checkConnectivity();
    final hasNet = conn.any((c) => c != ConnectivityResult.none);
    final isWifi = conn.contains(ConnectivityResult.wifi) ||
        conn.contains(ConnectivityResult.ethernet);
    if (!hasNet) {
      set(0, StepStatus.fail, 'Tidak ada koneksi Wi-Fi maupun data seluler',
          'Nyalakan Wi-Fi/data seluler, matikan mode pesawat, atau cek kabel/sinyal.');
      skipFrom(1, 'Dilewati karena tidak ada link');
      return;
    }
    String gateway = '';
    if (isWifi) {
      final info = NetworkInfo();
      String? ssid, ip, gw;
      try {
        ssid = await info.getWifiName();
        ip = await info.getWifiIP();
        gw = await info.getWifiGatewayIP();
      } catch (_) {}
      gateway = gw ?? '';
      set(
          0,
          StepStatus.ok,
          'Wi-Fi tersambung${ssid != null ? ' ($ssid)' : ''}'
          '${ip != null ? ', IP HP: $ip' : ''}');
    } else {
      final names = conn.map((c) => c.name).join(', ');
      set(0, StepStatus.ok, 'Tersambung lewat: $names');
    }

    // 1: Gateway
    start(1);
    if (!isWifi || gateway.isEmpty) {
      set(1, StepStatus.skipped,
          isWifi ? 'IP gateway tidak terbaca' : 'Pakai data seluler, tidak ada gateway lokal');
    } else {
      final g = await pingHost(gateway);
      if (g.ok) {
        set(1, StepStatus.ok, 'Gateway $gateway: ${g.describe()}');
      } else {
        set(1, StepStatus.warn, 'Gateway $gateway tidak membalas ping',
            'Router bisa jadi mati, terlalu jauh, atau memblokir ICMP/client isolation. Lanjut tes ke internet.');
      }
    }

    // 2: Internet
    start(2);
    var net = await pingHost('8.8.8.8');
    String netTarget = '8.8.8.8';
    if (!net.ok) {
      net = await pingHost('1.1.1.1');
      netTarget = '1.1.1.1';
    }
    if (net.ok) {
      set(2, StepStatus.ok, '$netTarget: ${net.describe()}');
    } else {
      bool tcpOk = false;
      try {
        final s = await Socket.connect('1.1.1.1', 443,
            timeout: const Duration(seconds: 5));
        s.destroy();
        tcpOk = true;
      } catch (_) {}
      if (tcpOk) {
        set(2, StepStatus.warn,
            'Ping ICMP ke IP publik gagal, tapi koneksi TCP berhasil',
            'Jaringan memblokir ICMP. Internet sebenarnya jalan.');
      } else {
        set(2, StepStatus.fail, 'Tidak bisa menjangkau IP publik (${net.error ?? 'timeout'})',
            'Masalah di ISP/routing (L3): router nggak punya internet, kuota habis, atau gateway putus.');
        skipFrom(3, 'Dilewati karena internet tidak terjangkau');
        return;
      }
    }

    // 3: DNS
    start(3);
    String targetIp = host;
    if (isIp(host)) {
      set(3, StepStatus.skipped, 'Target sudah berupa IP, DNS tidak diperlukan');
    } else {
      try {
        final sw = Stopwatch()..start();
        final addrs = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 6));
        sw.stop();
        if (addrs.isEmpty) throw const SocketException('Failed host lookup');
        targetIp = addrs.first.address;
        set(3, StepStatus.ok, '$host menjadi $targetIp (${sw.elapsedMilliseconds} ms)');
      } catch (e) {
        set(3, StepStatus.fail, 'Gagal resolve $host: ${describeSocketError(e)}',
            'IP publik terjangkau tapi domain gagal. Cek ejaan domain, ganti DNS (misal Private DNS dns.google), atau DNS ISP bermasalah.');
        skipFrom(4, 'Dilewati karena DNS gagal');
        return;
      }
    }

    // 4: Ping target
    start(4);
    final tp = await pingHost(targetIp);
    if (tp.ok) {
      set(4, StepStatus.ok, '$targetIp: ${tp.describe()}');
    } else {
      set(4, StepStatus.warn, '$targetIp tidak membalas ping (${tp.error ?? 'timeout'})',
          'Server bisa saja memblokir ICMP. Hasil tes TCP di bawah lebih menentukan.');
    }

    // 5: TCP
    start(5);
    try {
      final sw = Stopwatch()..start();
      final s = await Socket.connect(targetIp, port,
          timeout: const Duration(seconds: 6));
      sw.stop();
      s.destroy();
      set(5, StepStatus.ok, 'Port $port terbuka (${sw.elapsedMilliseconds} ms)');
    } catch (e) {
      set(5, StepStatus.fail, 'Port $port: ${describeSocketError(e)}',
          'Layer 4 bermasalah: port salah, layanan mati, atau firewall menolak/menahan paket.');
      skipFrom(6, 'Dilewati karena TCP gagal');
      return;
    }

    // 6: TLS
    start(6);
    if (port == 443) {
      try {
        final s = await SecureSocket.connect(host, port,
            timeout: const Duration(seconds: 8));
        final cert = s.peerCertificate;
        s.destroy();
        set(6, StepStatus.ok,
            'Handshake berhasil${cert != null ? ' (${cert.subject.split('CN=').last.split('/').first})' : ''}');
      } catch (e) {
        set(6, StepStatus.fail, describeSocketError(e),
            'Sertifikat tidak valid/kedaluwarsa, jam HP salah, atau ada proxy yang mencegat HTTPS.');
        skipFrom(7, 'Dilewati karena TLS gagal');
        return;
      }
    } else {
      set(6, StepStatus.skipped, 'Port bukan 443, TLS tidak dites');
    }

    // 7: HTTP
    start(7);
    final scheme = port == 443 ? 'https' : 'http';
    final portPart = (port == 443 || port == 80) ? '' : ':$port';
    final url = Uri.parse('$scheme://$host$portPart/');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final sw = Stopwatch()..start();
      final req = await client.getUrl(url);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      await resp.drain();
      sw.stop();
      final code = resp.statusCode;
      final d = 'HTTP $code ${resp.reasonPhrase} (${sw.elapsedMilliseconds} ms)';
      if (code < 400) {
        set(7, StepStatus.ok, d);
      } else if (code < 500) {
        set(7, StepStatus.warn, d,
            'Server terjangkau, tapi aplikasi membalas error klien (misal 403/404). Jaringan aman.');
      } else {
        set(7, StepStatus.fail, d,
            'Server terjangkau, tapi aplikasinya error di sisi server (L7).');
      }
    } catch (e) {
      set(7, StepStatus.fail, describeSocketError(e),
          'Layer aplikasi bermasalah: server lambat, memutus koneksi, atau redirect bermasalah.');
    } finally {
      client.close(force: true);
    }
  }
}
