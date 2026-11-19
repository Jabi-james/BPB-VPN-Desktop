import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'scanner_channel.dart';
import 'vpn_channel.dart';

/// Windows close/minimize-to-tray lifecycle. The tray remains available while the
/// main window is hidden, and Exit always shuts down the Go/Xray child first.
class WindowsLifecycle with WindowListener, TrayListener {
  WindowsLifecycle._(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;
  static const _choiceKey = 'windows.closeChoice';
  static const _minimizeChoice = 'minimize';
  static const _exitChoice = 'exit';

  static WindowsLifecycle? _instance;
  bool _handlingClose = false;
  bool _exiting = false;

  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (defaultTargetPlatform != TargetPlatform.windows || _instance != null) {
      return;
    }
    final lifecycle = WindowsLifecycle._(navigatorKey);
    _instance = lifecycle;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(lifecycle);
    trayManager.addListener(lifecycle);
    final trayIcon = File('${File(Platform.resolvedExecutable).parent.path}\\bpb_tray.ico');
    if (await trayIcon.exists()) await trayManager.setIcon(trayIcon.path);
    await trayManager.setToolTip('BPB VPN');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: 'Open BPB VPN'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'Exit'),
        ],
      ),
    );
  }

  @override
  void onWindowClose() {
    if (!_exiting) unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    if (_handlingClose || _exiting) return;
    _handlingClose = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_choiceKey);
      if (saved == _minimizeChoice) {
        await _minimize();
        return;
      }
      if (saved == _exitChoice) {
        await _exit();
        return;
      }

      final context = navigatorKey.currentContext;
      if (context == null) {
        await _minimize();
        return;
      }
      if (!context.mounted) return;
      var alwaysUse = false;
      final decision = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Close BPB VPN?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Would you like to minimize BPB VPN to the system tray or close it completely?'),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alwaysUse,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Always Use This Choice'),
                  onChanged: (value) => setDialogState(() => alwaysUse = value ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('minimize'),
                child: const Text('Minimize'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop('exit'),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
      if (decision == null) return;
      if (alwaysUse) await prefs.setString(_choiceKey, decision);
      if (decision == _minimizeChoice) {
        await _minimize();
      } else {
        await _exit();
      }
    } finally {
      _handlingClose = false;
    }
  }

  Future<void> _minimize() async {
    await windowManager.hide();
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await ScannerChannel.shutdownDesktop();
      await VpnChannel.shutdownWindows();
    } finally {
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      unawaited(_showWindow());
    } else if (menuItem.key == 'exit_app') {
      unawaited(_exit());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }
}
