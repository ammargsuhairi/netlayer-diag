import 'package:flutter/material.dart';

import 'home_page.dart';
import 'live_ping_page.dart';

void main() => runApp(const NetLayerApp());

class NetLayerApp extends StatelessWidget {
  const NetLayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetLayer Diag',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: index,
          children: const [DiagnosticPage(), LivePingPage()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.layers), label: 'Diagnosa'),
          NavigationDestination(icon: Icon(Icons.network_ping), label: 'Ping Live'),
        ],
      ),
    );
  }
}
