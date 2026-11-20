import 'dart:async';

import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/home_page.dart';
import 'ui/setup_wizard.dart';
import 'ui/theme.dart';
import 'services/windows_lifecycle.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init(cleanStart: args.contains('--bpb-clean-start'));
  await WindowsLifecycle.initialize(_navigatorKey, state);
  runApp(BpbApp(state: state));
  if (args.contains('--bpb-elevated-tun')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Let the unelevated copy and its core process exit before binding port 10880 again.
      unawaited(Future<void>.delayed(const Duration(seconds: 2), state.connect));
    });
  }
}

class BpbApp extends StatelessWidget {
  final AppState state;
  const BpbApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      // Rebuilds when the theme or global text scale changes in Settings.
      child: ListenableBuilder(
        listenable: Listenable.merge([state.themeColor, state.themeMode, state.fontScale]),
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'BPB VPN',
          debugShowCheckedModeBanner: false,
          // Android can draw the app into the navigation bar area (notably with
          // gesture navigation). Keep every route's content above that inset.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(state.fontScale.value),
            ),
            child: SafeArea(
              top: false,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          theme: buildTheme(Brightness.light, state.themeColor.value),
          darkTheme: buildTheme(Brightness.dark, state.themeColor.value),
          themeMode: state.themeMode.value,
          home: const _Root(),
        ),
      ),
    );
  }
}

/// The setup wizard until a VPN worker is set up, then the home page.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final needsSetup = AppScope.of(context).needsSetup;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: needsSetup ? const SetupWizard(key: ValueKey('setup')) : const HomePage(key: ValueKey('home')),
    );
  }
}
