import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'screens/connect_screen.dart';
import 'screens/file_print_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/receipt_screen.dart';
import 'screens/settings_screen.dart';
import 'services/history.dart';
import 'services/integration.dart';
import 'services/printer_service.dart';
import 'services/settings.dart';
import 'services/warranty.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AppSettings.instance.load();
  await PrintHistory.instance.load();
  await WarrantyStore.instance.load();
  runApp(const LeopardoApp());
}

class LeopardoApp extends StatelessWidget {
  const LeopardoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Leopardo',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        scaffoldMessengerKey: messengerKey,
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
    // Pedidos de impressão de outros apps e sites (leopardo://, br.com.leopardo.PRINT).
    Integration.onRequest = _onPrintRequest;
    Integration.init();
    // Reconecta à última impressora usada.
    WidgetsBinding.instance.addPostFrameCallback((_) => PrinterService.instance.reconnectLast());
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  void _toast(String text) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onPrintRequest(PrintRequest r) async {
    _toast('Imprimindo pedido recebido…');
    try {
      await Integration.print(r);
      _toast('Pedido impresso.');
    } catch (e) {
      _toast('Não foi possível imprimir: $e');
      if (!PrinterService.instance.isConnected) {
        navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const ConnectScreen()));
      }
    }
  }

  void _openShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final f = files.first;
    if (f.path.isEmpty || f.path.startsWith('leopardo:')) return; // tratado pela integração
    if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
      // Texto compartilhado (ex.: pedido do WhatsApp): abre já preenchido para imprimir.
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ReceiptScreen(initialText: f.path),
      ));
      return;
    }
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => FilePrintScreen(path: f.path, sourceLabel: 'Recebido de outro app'),
    ));
  }

  void _select(int i) {
    setState(() {
      if (i == 3 && _tab != 3) _settingsVersion++; // recarrega os campos de Ajustes
      _tab = i;
    });
    if (i == 1) {
      PrinterService.instance.loadNativeDevices();
      if (!PrinterService.instance.isConnected && !PrinterService.instance.scanning) {
        PrinterService.instance.startScan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onOpenSettings: () => _select(3), onOpenHistory: () => _select(2)),
          const ConnectScreen(asTab: true),
          const HistoryScreen(),
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
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history), label: 'Histórico'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
