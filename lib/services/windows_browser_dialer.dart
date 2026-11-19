import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

/// Keeps Xray's Browser Dialer page alive in an invisible WebView2 controller.
class WindowsBrowserDialer {
  WindowsBrowserDialer._();

  static const String address = 'http://127.0.0.1:10832/';
  static WebviewController? _controller;

  static Future<void> prepare() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) return;
    if (_controller != null) return;

    final version = await WebviewController.getWebViewVersion();
    if (version == null) {
      throw StateError(
        'Microsoft Edge WebView2 Runtime is required for Browser Dialer. '
        'Install the Evergreen Runtime and try again.',
      );
    }

    await WebviewController.initializeEnvironment(
      additionalArguments: '--no-proxy-server',
    );

    final controller = WebviewController();
    try {
      await controller.initialize();
      await controller.setSize(const Size(1280, 720));
      _controller = controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  static Future<void> load() async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('Browser Dialer WebView was not initialized.');
    }
    await controller.loadUrl(address);
  }

  static Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.stop();
      } finally {
        await controller.dispose();
      }
    }
  }
}
