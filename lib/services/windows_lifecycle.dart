import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

enum _CloseChoice { minimize, close }

/// Windows close-button behavior and the system-tray entry point.
class WindowsLifecycle with WindowListener, TrayListener {
  WindowsLifecycle._(this._onExit);

  static final navigatorKey = GlobalKey<NavigatorState>();
  static const _preference = 'windows.closeChoice';
  static WindowsLifecycle? _instance;
  final Future<void> Function() _onExit;
  SharedPreferences? _preferences;
  bool _closing = false;

  static Future<void> initialize(Future<void> Function() onExit) async {
    final lifecycle = WindowsLifecycle._(onExit);
    _instance = lifecycle;
    lifecycle._preferences = await SharedPreferences.getInstance();
    await windowManager.ensureInitialized();
    windowManager.addListener(lifecycle);
    await windowManager.setPreventClose(true);
    trayManager.addListener(lifecycle);
    await trayManager.setIcon('app_icon.ico');
    await trayManager.setToolTip('BPB VPN');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Open BPB VPN'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: 'Exit'),
    ]));
  }

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    final saved = _preferences?.getString(_preference);
    if (saved == _CloseChoice.minimize.name) {
      await windowManager.hide();
      return;
    }
    if (saved == _CloseChoice.close.name) {
      await _exit();
      return;
    }
    final context = navigatorKey.currentContext;
    if (context == null) return;
    var remember = false;
    final choice = await showDialog<_CloseChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Close BPB VPN?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Would you like to minimize the app to the system tray or close it completely?'),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: remember,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Always Use This Choice'),
                onChanged: (value) => setDialogState(() => remember = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, _CloseChoice.minimize), child: const Text('Minimize')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, _CloseChoice.close), child: const Text('Close')),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (remember) await _preferences?.setString(_preference, choice.name);
    if (choice == _CloseChoice.minimize) {
      await windowManager.hide();
    } else {
      await _exit();
    }
  }

  Future<void> _exit() async {
    if (_closing) return;
    _closing = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await _onExit();
  }

  Future<void> _restore() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => unawaited(_restore());

  @override
  void onTrayIconDoubleClick() => unawaited(_restore());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') unawaited(_restore());
    if (menuItem.key == 'exit') unawaited(_exit());
  }
}
