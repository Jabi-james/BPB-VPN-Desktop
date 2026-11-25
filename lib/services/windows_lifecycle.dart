import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../models/settings.dart';
import '../state/app_state.dart';
import 'scanner_channel.dart';
import 'vpn_channel.dart';

/// Windows close/minimize-to-tray lifecycle. The tray remains available while the
/// main window is hidden, and Exit always shuts down the Go/Xray child first.
class WindowsLifecycle with WindowListener, TrayListener {
  WindowsLifecycle._(this.navigatorKey, this.appState);

  final GlobalKey<NavigatorState> navigatorKey;
  final AppState appState;
  static const _choiceKey = 'windows.closeChoice';
  static const _minimizeChoice = 'minimize';
  static const _exitChoice = 'exit';

  static WindowsLifecycle? _instance;
  bool _handlingClose = false;
  bool _exiting = false;
  bool _windowWasBlurred = false;
  late final MenuItem _proxyMenuItem;
  late final MenuItem _systemProxyMenuItem;
  late final MenuItem _tunMenuItem;
  bool? _lastIconsConnected;
  Future<void> _iconUpdateQueue = Future<void>.value();

  static File _connectionIconFile(bool connected) {
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final fileName = connected ? 'bpb_tray_connected.ico' : 'bpb_tray.ico';
    return File('$executableDirectory\\$fileName');
  }

  /// Keep both Windows shell icons in sync with the actual VPN connection state.
  void _updateConnectionIcons() {
    if (_exiting) return;
    final connected = appState.isConnected;
    if (_lastIconsConnected == connected) return;
    _lastIconsConnected = connected;

    _iconUpdateQueue = _iconUpdateQueue.then((_) async {
      if (_exiting) return;
      final icon = _connectionIconFile(connected);
      if (!await icon.exists()) {
        debugPrint('BPB: connection-state icon not found: ${icon.path}');
        return;
      }
      await trayManager.setIcon(icon.path);
      if (_exiting) return;
      await windowManager.setIcon(icon.path);
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('BPB: failed to update connection-state icons: $error');
    });
  }

  /// Keep exactly one check mark beside the connection mode currently selected in the app.
  void _updateTrayMode() {
    if (_exiting) return;
    final mode = appState.device.appMode;
    _proxyMenuItem.checked = mode == AppMode.proxy;
    _systemProxyMenuItem.checked = mode == AppMode.systemProxy;
    _tunMenuItem.checked = mode == AppMode.vpn;
  }

  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey, AppState appState) async {
    if (defaultTargetPlatform != TargetPlatform.windows || _instance != null) {
      return;
    }
    final lifecycle = WindowsLifecycle._(navigatorKey, appState);
    _instance = lifecycle;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(lifecycle);
    trayManager.addListener(lifecycle);
    final connected = appState.isConnected;
    final initialIcon = _connectionIconFile(connected);
    if (await initialIcon.exists()) {
      await trayManager.setIcon(initialIcon.path);
      await windowManager.setIcon(initialIcon.path);
    }
    lifecycle._lastIconsConnected = connected;
    await trayManager.setToolTip('BPB VPN');
    lifecycle._proxyMenuItem = MenuItem.checkbox(
      key: 'mode_proxy',
      label: 'Proxy service only',
      checked: appState.device.appMode == AppMode.proxy,
    );
    lifecycle._systemProxyMenuItem = MenuItem.checkbox(
      key: 'mode_system_proxy',
      label: 'Set system proxy',
      checked: appState.device.appMode == AppMode.systemProxy,
    );
    lifecycle._tunMenuItem = MenuItem.checkbox(
      key: 'mode_tun',
      label: 'TUN mode (all apps)',
      checked: appState.device.appMode == AppMode.vpn,
    );
    appState.addListener(lifecycle._updateTrayMode);
    appState.addListener(lifecycle._updateConnectionIcons);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: 'Open'),
          MenuItem.separator(),
          lifecycle._proxyMenuItem,
          lifecycle._systemProxyMenuItem,
          lifecycle._tunMenuItem,
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'Quit'),
        ],
      ),
    );
  }

  @override
  void onWindowBlur() {
    _windowWasBlurred = true;
  }

  @override
  void onWindowFocus() {
    if (!_windowWasBlurred) return;
    _windowWasBlurred = false;
    if (appState.isConnected) {
      unawaited(appState.checkConnectionHealthNow());
    }
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
        barrierDismissible: true,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('What would you like to do?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Minimize BPB VPN to the system tray or close it completely?'),
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alwaysUse,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Always use this choice', style: TextStyle(fontSize: 12)),
                  onChanged: (value) => setDialogState(() => alwaysUse = value ?? false),
                ),
              ],
            ),
            actions: [
              FilledButton.tonalIcon(
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop('minimize'),
                icon: const Icon(Icons.minimize_rounded),
                label: const Text('Minimize'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(dialogContext).pop('exit'),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Close'),
              ),
            ],
          ),
        ),
      );
      // Clicking outside only dismisses this confirmation dialog; keep the app visible.
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

    // Close the visible window immediately. Keep this process alive in the
    // background until every helper/core has finished shutting down.
    try {
      await windowManager.hide();
    } catch (_) {
      // Continue shutdown even if the window could not be hidden.
    }
    unawaited(_finishExit());
  }

  Future<void> _finishExit() async {
    appState.removeListener(_updateTrayMode);
    appState.removeListener(_updateConnectionIcons);
    try {
      // Independent helpers shut down concurrently so their waits do not add up.
      await Future.wait([
        ScannerChannel.shutdownDesktop(),
        VpnChannel.shutdownWindows(),
      ]);
    } finally {
      try {
        await trayManager.destroy();
      } finally {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      }
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == 'show_window') {
      unawaited(_showWindow());
    } else if (key == 'mode_proxy') {
      unawaited(_selectMode(AppMode.proxy));
    } else if (key == 'mode_system_proxy') {
      unawaited(_selectMode(AppMode.systemProxy));
    } else if (key == 'mode_tun') {
      unawaited(_selectMode(AppMode.vpn));
    } else if (key == 'exit_app') {
      unawaited(_exit());
    }
  }

  Future<void> _selectMode(AppMode mode) async {
    if (_exiting || appState.isBusy) return;
    appState.setAppMode(mode);
    await _showWindow();
    await appState.reconnect();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }
}
