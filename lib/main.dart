import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'screens/connect_screen.dart';
import 'screens/file_print_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/printer_service.dart';
import 'services/settings.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AppSettings.instance.load();
  runApp(const LeopardoApp());
}

class LeopardoApp extends StatelessWidget {
  const LeopardoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Leopardo',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildTheme(),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  int _settingsVersion = 0;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    // Arquivos compartilhados com o app (ex.: PDF do WhatsApp).
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(_openShared, onError: (_) {});
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _openShared(files);
      ReceiveSharingIntent.instance.reset();
    });
    // Reconecta à última impressora usada.
    WidgetsBinding.instance.addPostFrameCallback((_) => PrinterService.instance.reconnectLast());
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  void _openShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final f = files.first;
    if (f.path.isEmpty) return;
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => FilePrintScreen(path: f.path, sourceLabel: 'Recebido de outro app'),
    ));
  }

  void _select(int i) {
    setState(() {
      if (i == 2 && _tab != 2) _settingsVersion++; // recarrega os campos de Ajustes
      _tab = i;
    });
    if (i == 1 && !PrinterService.instance.isConnected && !PrinterService.instance.scanning) {
      PrinterService.instance.startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onOpenSettings: () => _select(2)),
          const ConnectScreen(asTab: true),
          SettingsScreen(key: ValueKey(_settingsVersion)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(
              icon: Icon(Icons.print_outlined), selectedIcon: Icon(Icons.print), label: 'Impressoras'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
