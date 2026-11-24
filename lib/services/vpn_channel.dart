import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

import 'windows_browser_dialer.dart';

import 'mitm_ca.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting }

class VpnStateEvent {
  final VpnStatus status;
  final String? error;
  final DateTime? connectedAt;

  /// What the Psiphon / Tor exit is doing ("Tor 45% · Loading relay descriptors",
  /// "Psiphon reconnecting…"); null otherwise.
  final String? detail;
  const VpnStateEvent(this.status, this.error, this.connectedAt, this.detail);
}

class InstalledApp {
  final String packageName;
  final String label;
  final bool isSystem;
  final Uint8List? icon;
  const InstalledApp(this.packageName, this.label, this.isSystem, this.icon);
}

/// Bridge to the Android VPN service and Xray core (see MainActivity.kt).
class VpnChannel {
  static const _methods = MethodChannel('bpb/core');
  static const _events = EventChannel('bpb/state');
  static Future<bool>? _supportsAppendHttpProxy;

  // Windows runs BPB's Go/Xray host as a child process. BPB: marks protocol replies,
  // leaving ordinary Xray log lines separate from the command channel.
  static Process? _windowsProcess;
  static bool _windowsShuttingDown = false;
  static Completer<Map<String, dynamic>>? _windowsPending;
  static Future<void> _windowsCommandTail = Future<void>.value();
  static final _windowsStates = StreamController<VpnStateEvent>.broadcast();
  static DateTime? _windowsConnectedAt;
  static VpnStatus _windowsStatus = VpnStatus.disconnected;
  static final List<String> _windowsLogLines = [];
  static String? _windowsAetherLogPath;
  static const int _windowsMaxLogLines = 2000;

  static void configureAetherLogPath(String directory) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _windowsAetherLogPath = '$directory${Platform.pathSeparator}aether.log';
    }
  }

  /// App-side diagnostics are added to the Windows core log stream.
  static void appendLog(String line) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _appendWindowsLog(line);
    }
  }

  static void _appendWindowsLog(String line) {
    if (line.isEmpty) return;
    _windowsLogLines.add(line);
    if (_windowsLogLines.length > _windowsMaxLogLines) {
      _windowsLogLines.removeRange(0, _windowsLogLines.length - _windowsMaxLogLines);
    }
  }

  static void _emitWindowsState(
    VpnStatus status, [
    String? error,
    String? detail,
  ]) {
    _windowsStatus = status;
    _windowsStates.add(VpnStateEvent(
      status,
      error,
      status == VpnStatus.connected ? (_windowsConnectedAt ??= DateTime.now()) : null,
      detail,
    ));
    if (status == VpnStatus.connecting || status == VpnStatus.disconnected) {
      _windowsConnectedAt = null;
    }
  }

  static Future<void> _ensureWindowsProcess() async {
    if (_windowsProcess != null) return;
    final executable = File(Platform.resolvedExecutable).parent.uri
        .resolve('bpb_core.exe').toFilePath();
    if (!await File(executable).exists()) {
      throw StateError('BPB core executable was not found: $executable');
    }
    final process = await Process.start(executable, const []);
    _windowsProcess = process;
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (!line.startsWith('BPB:')) {
        _appendWindowsLog(line);
        return;
      }
      try {
        final value = jsonDecode(line.substring(4));
        if (value is Map && value['event'] == 'state') {
          _emitWindowsState(
            _windowsStatus,
            null,
            value['detail'] as String?,
          );
          return;
        }
        final pending = _windowsPending;
        if (value is Map && pending != null && !pending.isCompleted) {
          pending.complete(Map<String, dynamic>.from(value));
        }
      } catch (error) {
        _appendWindowsLog('BPB protocol decode error: $error');
      }
    });
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      _appendWindowsLog('[stderr] $line');
    });
    unawaited(process.exitCode.then((code) {
      if (identical(_windowsProcess, process)) _windowsProcess = null;
      final pending = _windowsPending;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(StateError('BPB core exited (code $code).'));
      }
      _windowsPending = null;
      _emitWindowsState(VpnStatus.disconnected, 'BPB core exited (code $code).');
    }));
  }

  static Future<Map<String, dynamic>> _sendWindowsCommand(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_windowsShuttingDown) throw StateError('BPB is shutting down.');
    // Serialize all requests on the single-line Go protocol. Polling must queue
    // behind long startup commands rather than fail as a competing command.
    final previous = _windowsCommandTail;
    final release = Completer<void>();
    _windowsCommandTail = release.future;
    await previous;
    try {
      if (_windowsShuttingDown) throw StateError('BPB is shutting down.');
      await _ensureWindowsProcess();
      final process = _windowsProcess!;
      final completer = Completer<Map<String, dynamic>>();
      _windowsPending = completer;
      try {
        process.stdin.writeln(jsonEncode(request));
        await process.stdin.flush();
        try {
          return await completer.future.timeout(timeout);
        } on TimeoutException {
          // Do not let a late response be consumed as the next command's response.
          await Process.run('taskkill.exe', ['/T', '/F', '/PID', process.pid.toString()]);
          process.kill();
          try { await process.exitCode.timeout(const Duration(seconds: 3)); } catch (_) {}
          if (identical(_windowsProcess, process)) _windowsProcess = null;
          throw StateError('BPB core command timed out; the core process was terminated.');
        }
      } finally {
        if (identical(_windowsPending, completer)) _windowsPending = null;
      }
    } finally {
      release.complete();
    }
  }

  static Future<void> provisionAetherIdentities(String configDir) async {
    if (!Platform.isWindows) return;
    final result = await _sendWindowsCommand({
      'command': 'provisionAether',
      'aetherConfigDir': configDir,
    }, timeout: const Duration(minutes: 5));
    if (result['ok'] != true) {
      throw StateError(result['error'] as String? ?? 'Aether first-run provisioning failed.');
    }
  }

  static Future<void> renewAetherMasqueIdentity(String configDir) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Aether MASQUE identity renewal is available on Windows only.');
    }
    final result = await _sendWindowsCommand({
      'command': 'renewAetherMasque',
      'aetherConfigDir': configDir,
    }, timeout: const Duration(minutes: 5));
    if (result['ok'] != true) {
      throw StateError(result['error'] as String? ?? 'Aether MASQUE identity renewal failed.');
    }
  }

  /// Sends cancellation out-of-band while the scan command is still awaiting its response.
  static Future<void> cancelAetherEndpointScan() async {
    if (!Platform.isWindows) return;
    final process = _windowsProcess;
    if (process == null) return;
    process.stdin.writeln(jsonEncode({'command': 'cancelAetherScan'}));
    await process.stdin.flush();
  }

  static Future<void> renewAetherWgIdentity(String configDir) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Aether WARP identity renewal is available on Windows only.');
    }
    final result = await _sendWindowsCommand({
      'command': 'renewAetherWg',
      'aetherConfigDir': configDir,
    }, timeout: const Duration(minutes: 5));
    if (result['ok'] != true) {
      throw StateError(result['error'] as String? ?? 'Aether WARP identity renewal failed.');
    }
  }

  static Future<List<String>> scanAetherEndpoints({
    required String protocol,
    required String configDir,
    required Map<String, String> environment,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Aether endpoint scanning is available on Windows only.');
    }
    final result = await _sendWindowsCommand({
      'command': 'scanAether',
      'aetherProtocol': protocol,
      'aetherConfigDir': configDir,
      'aetherEnvironment': environment,
    }, timeout: const Duration(minutes: 6));
    if (result['ok'] != true) {
      throw StateError(result['error'] as String? ?? 'Aether endpoint scan failed.');
    }
    return (result['aetherEndpoints'] as List? ?? const [])
        .whereType<String>()
        .toList();
  }

  static Future<bool> _isWindowsElevated() async {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
    ]);
    return result.exitCode == 0 &&
        result.stdout.toString().trim().toLowerCase() == 'true';
  }

  static Future<void> _startWindows({
    required Map<String, dynamic> config,
    required String appMode,
    required bool verifyConnection,
    required bool browserDialer,
    String? exit,
    bool exitDirect = false,
    String exitRegion = '',
    Map<String, dynamic>? psiphonConfig,
    String? torBridge,
    List<String> torCustomBridges = const [],
    String? aetherConfigDir,
    String? aetherProtocol,
    Map<String, String>? aetherEnvironment,
    Map<String, dynamic>? sshConfig,
  }) async {
    _emitWindowsState(VpnStatus.connecting);
    try {
      final result = await _sendWindowsCommand({
        'command': 'start',
        'mode': appMode,
        'config': jsonEncode(config),
        'browserDialer': browserDialer,
        'exit': exit,
        'exitDirect': exitDirect,
        'exitRegion': exitRegion,
        'psiphonConfig': psiphonConfig == null ? null : jsonEncode(psiphonConfig),
        'torBridge': torBridge,
        'torCustomBridges': torCustomBridges,
        'aetherConfigDir': aetherConfigDir,
        'aetherProtocol': aetherProtocol,
        'aetherEnvironment': aetherEnvironment,
        'sshConfig': sshConfig == null ? null : jsonEncode(sshConfig),
        // Do not report CONNECTED until Xray can complete a request through its outbound.
        'verifyConnection': verifyConnection,
      }, timeout: exit == null && aetherProtocol == null
          ? const Duration(seconds: 30)
          : const Duration(minutes: 16));
      if (result['ok'] != true) {
        throw StateError(result['error'] as String? ?? 'BPB core failed to start.');
      }
      if (browserDialer) await WindowsBrowserDialer.load();
      _emitWindowsState(VpnStatus.connected);
    } catch (error) {
      // A failed start must release the previous core session before another mode is tried.
      try { await _sendWindowsCommand({'command': 'stop'}); } catch (_) {}
      await WindowsBrowserDialer.stop();
      _emitWindowsState(VpnStatus.disconnected, '$error');
      rethrow;
    }
  }

  static Future<void> _cancelWindowsStart(Process process) async {
    // The Go host accepts this out-of-band command while its start command is
    // waiting for Tor/Psiphon. It has no reply; the original start request does.
    try {
      process.stdin.writeln(jsonEncode({'command': 'cancel'}));
      await process.stdin.flush();
    } catch (_) {
      // The child may already have exited.
    }
  }

  static Future<void> _stopWindows() async {
    if (_windowsProcess == null) {
      await WindowsBrowserDialer.stop();
      _emitWindowsState(VpnStatus.disconnected);
      return;
    }
    final wasConnecting = _windowsStatus == VpnStatus.connecting;
    _emitWindowsState(VpnStatus.disconnecting);
    if (wasConnecting) await _cancelWindowsStart(_windowsProcess!);
    try {
      final result = await _sendWindowsCommand({'command': 'stop'})
          .timeout(const Duration(seconds: 12));
      if (result['ok'] != true) {
        throw StateError(result['error'] as String? ?? 'BPB core failed to stop.');
      }
      _emitWindowsState(VpnStatus.disconnected);
    } catch (error) {
      _emitWindowsState(VpnStatus.disconnected, '$error');
      rethrow;
    } finally {
      await WindowsBrowserDialer.stop();
    }
  }


  static Future<bool> get supportsAppendHttpProxy {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    return _supportsAppendHttpProxy ??= _methods
        .invokeMethod<bool>('supportsAppendHttpProxy')
        .then((supported) => supported ?? false);
  }

  static Stream<VpnStateEvent> get states {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) return _windowsStates.stream;
    return _events.receiveBroadcastStream().map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      final at = (map['connectedAt'] as num?)?.toInt() ?? 0;
      return VpnStateEvent(
        VpnStatus.values.byName(map['state'] as String),
        map['error'] as String?,
        at > 0 ? DateTime.fromMillisecondsSinceEpoch(at) : null,
        map['detail'] as String?,
      );
    });
  }

  /// Asks for VPN permission if needed; true when granted.
  /// Asks for notification permission and, when [vpn], the VPN permission.
  static Future<bool> prepare({bool vpn = true}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) return true;
    return await _methods.invokeMethod<bool>('prepare', {'vpn': vpn}) ?? false;
  }

  static Future<void> start({
    required Map<String, dynamic> config,
    required String remark,
    required String perAppMode,
    required List<String> apps,
    required int mtu,
    bool appendHttpProxy = false,
    bool proxyOnly = false,
    String appMode = 'vpn',
    String? exit,
    bool exitDirect = false,
    String exitRegion = '',
    String? torBridge,
    List<String> torCustomBridges = const [],
    String? aetherConfigDir,
    String? aetherProtocol,
    Map<String, String>? aetherEnvironment,
    Map<String, dynamic>? psiphonConfig,
    Map<String, dynamic>? sshConfig,
    bool browserDialer = false,
    bool verifyConnection = false,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      if (browserDialer && appMode == 'vpn') {
        throw UnsupportedError(
          'Windows Browser Dialer currently supports Proxy and System Proxy modes. TUN support is planned for the TUN stage.',
        );
      }
      if (perAppMode != 'off') {
        throw UnsupportedError('Per-app routing is not available on Windows yet.');
      }
      if (browserDialer) await WindowsBrowserDialer.prepare();
      if (appMode == 'vpn' && !await _isWindowsElevated()) {
        final executable = Platform.resolvedExecutable.replaceAll("'", "''");
        final script = "try { Start-Process -FilePath '$executable' -Verb RunAs -ArgumentList '--bpb-elevated-tun' -ErrorAction Stop; exit 0 } catch { [Console]::Error.WriteLine(\$_.Exception.Message); exit 1 }";
        final launch = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]);
        if (launch.exitCode != 0) {
          throw StateError(
            'Windows TUN requires Administrator permission. '
            '${launch.stderr.toString().trim()}',
          );
        }
        // The elevated copy restores the saved settings and starts the TUN session.
        io.exit(0);
      }
      await _startWindows(
        config: config,
        appMode: appMode,
        verifyConnection: verifyConnection,
        browserDialer: browserDialer,
        exit: exit,
        exitDirect: exitDirect,
        exitRegion: exitRegion,
        psiphonConfig: psiphonConfig,
        torBridge: torBridge,
        torCustomBridges: torCustomBridges,
        aetherConfigDir: aetherConfigDir,
        aetherProtocol: aetherProtocol,
        aetherEnvironment: aetherEnvironment,
        sshConfig: sshConfig,
      );
      return;
    }
    await _methods.invokeMethod('start', {
    'config': jsonEncode(config),
    'remark': remark,
    'perAppMode': perAppMode,
    'apps': apps,
    'mtu': mtu,
    'appendHttpProxy': appendHttpProxy,
    'proxyOnly': proxyOnly,
    'appMode': appMode,
    // Starts that exit process ("psiphon" / "tor"); null for none.
    'exit': exit,
    // The Psiphon / Tor type: the exit connects by itself, not through Xray's psiphon-in / tor-in.
    'exitDirect': exitDirect,
    // The exit's region; "" for the fastest.
    'exitRegion': exitRegion,
    // Tor type: direct, a built-in bridge transport, or custom (torCustomBridges).
    'torBridge': torBridge,
    'torCustomBridges': torCustomBridges,
    'aetherConfigDir': aetherConfigDir,
    // Psiphon config fields for the mode, added to the app's psiphon_config.json (see PsiphonExit.kt).
    'psiphonConfig': psiphonConfig == null ? null : jsonEncode(psiphonConfig),
    // Worker's Browser Dialer: Xray's WebSockets are opened by a WebView (see BrowserDialer.kt).
    'browserDialer': browserDialer,
    'verifyConnection': verifyConnection,
    });
  }

  /// Tests a DNS server through the Go networking module. Latency is the DNS lookup time;
  /// null latency means the server failed its DNS lookup or HTTP 204 validation.
  static Future<({bool ok, double? latency})> checkDns(
    Map<String, dynamic> request,
  ) async {
    final String? raw;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final result = await _sendWindowsCommand({
        'command': 'checkDns',
        'dns': jsonEncode(request),
      });
      raw = result['dns'] as String?;
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      raw = await _methods.invokeMethod<String>(
        'checkDns',
        jsonEncode(request),
      );
    } else {
      throw UnsupportedError('DNS server testing is not available on this platform.');
    }
    if (raw == null || raw.isEmpty) throw StateError('DNS test returned no result.');
    final response = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final ok = response['ok'] == true;
    final latency = response['latency'];
    return (ok: ok, latency: ok && latency is num ? latency.toDouble() : null);
  }

  /// The end of Xray's log for the current/last connection.
  static Future<String> readLog({String log = 'xray'}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      if (log == 'xray') return _windowsLogLines.join('\n');
      if (log == 'ssh') {
        return _windowsLogLines.where((line) => line.contains('[SSH]')).join('\n');
      }
      if (log == 'aether') {
        final path = _windowsAetherLogPath;
        if (path == null) return '';
        try {
          return await File(path).readAsString(encoding: utf8);
        } on FileSystemException {
          return '';
        }
      }
      if (log != 'tor' && log != 'psiphon') return '';
      final file = File(
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}${log == 'tor' ? 'tor.log' : 'psiphon.log'}',
      );
      try {
        return await file.readAsString(encoding: utf8);
      } on FileSystemException {
        return '';
      }
    }
    return await _methods.invokeMethod<String>('readLog', {'log': log}) ?? '';
  }

  /// Bytes in each log ("xray", "tor", "psiphon") since the last connect.
  static Future<Map<String, int>> logSizes() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final root = File(Platform.resolvedExecutable).parent.path;
      Future<int> sizeOf(String name) async {
        try {
          return await File('$root${Platform.pathSeparator}$name').length();
        } on FileSystemException {
          return 0;
        }
      }
      return {
        'xray': utf8.encode(_windowsLogLines.join('\n')).length,
        'ssh': utf8.encode(
          _windowsLogLines.where((line) => line.contains('[SSH]')).join('\n'),
        ).length,
        'tor': await sizeOf('tor.log'),
        'psiphon': await sizeOf('psiphon.log'),
        'aether': _windowsAetherLogPath == null
            ? 0
            : await _fileSize(_windowsAetherLogPath!),
      };
    }
    return (await _methods.invokeMapMethod<String, int>('logSizes')) ?? const {};
  }

  static Future<int> _fileSize(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }

  static Future<void> clearLog() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _windowsLogLines.clear();
      final root = File(Platform.resolvedExecutable).parent.path;
      for (final name in ['tor.log', 'psiphon.log']) {
        try {
          await File('$root${Platform.pathSeparator}$name').writeAsString('');
        } on FileSystemException {
          // A log that has not been created yet is already empty.
        }
      }
      final aetherLog = _windowsAetherLogPath;
      if (aetherLog != null) {
        try {
          await File(aetherLog).writeAsString('');
        } on FileSystemException {
          // A log that has not been created yet is already empty.
        }
      }
      return;
    }
    await _methods.invokeMethod('clearLog');
  }

  /// Saves [content] as [name] and opens the share sheet (Android) or a Save As dialog (Windows).
  static Future<void> shareFile({required String name, required String content, String title = 'Share'}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await _saveWindowsFile(name: name, content: content, title: title);
      return;
    }
    await _methods.invokeMethod('shareFile', {'name': name, 'content': content, 'title': title});
  }

  /// Shows a native Windows Save As dialog and returns the saved path.
  static Future<String?> _saveWindowsFile({
    required String name,
    required String content,
    String title = 'Save BPB file',
  }) async {
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.SaveFileDialog
$d.Title = $env:BPB_DIALOG_TITLE
$d.FileName = $env:BPB_DEFAULT_FILE_NAME
$d.Filter = 'BPB and JSON files (*.json)|*.json|All files (*.*)|*.*'
$d.AddExtension = $true
$d.DefaultExt = 'json'
if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::Out.Write($d.FileName)
}
''';
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-STA', '-Command', script],
      environment: {
        'BPB_DIALOG_TITLE': title,
        'BPB_DEFAULT_FILE_NAME': name,
      },
    );
    if (result.exitCode != 0) {
      throw StateError('Windows Save As dialog failed: ${result.stderr}');
    }
    final path = (result.stdout as String).trim();
    if (path.isEmpty) return null;
    await File(path).writeAsString(content, encoding: utf8, flush: true);
    return path;
  }

  /// Saves [content] as [name] in a Save As dialog on Windows or Downloads on Android.
  /// Returns the path, or null if the user cancelled.
  static Future<String?> saveFile({required String name, required String content}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return _saveWindowsFile(name: name, content: content);
    }
    return _methods.invokeMethod<String>('saveFile', {'name': name, 'content': content});
  }

  /// Opens the system file picker and returns the chosen file's name and text, or null if cancelled.
  static Future<({String name, String content})?> pickFile() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Title = 'Import BPB settings'
$d.Filter = 'BPB and JSON files (*.json)|*.json|All files (*.*)|*.*'
$d.CheckFileExists = $true
if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::Out.Write($d.FileName)
}
''';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-STA', '-Command', script],
      );
      if (result.exitCode != 0) {
        throw StateError('Windows file picker failed: ${result.stderr}');
      }
      final path = (result.stdout as String).trim();
      if (path.isEmpty) return null;
      final file = File(path);
      return (name: file.uri.pathSegments.last, content: await file.readAsString());
    }
    final file = await _methods.invokeMapMethod<String, String>('pickFile');
    if (file == null) return null;
    return (name: file['name'] ?? '', content: file['content'] ?? '');
  }

  /// Gracefully asks the Windows Go host to stop Xray and restore system proxy,
  /// then force-terminates the child if it does not exit promptly.
  static Future<void> shutdownWindows() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    _windowsShuttingDown = true;
    final process = _windowsProcess;
    if (process == null) {
      try {
        await WindowsBrowserDialer.stop().timeout(const Duration(seconds: 1));
      } catch (_) {}
      return;
    }
    if (_windowsStatus == VpnStatus.connecting) {
      await _cancelWindowsStart(process);
    }
    // Do not queue shutdown behind periodic status/traffic requests. Send it
    // directly, then impose a short hard deadline so closing the window stays responsive.
    try {
      process.stdin.writeln(jsonEncode({'command': 'shutdown'}));
      await process.stdin.flush().timeout(const Duration(milliseconds: 700));
    } catch (error) {
      _appendWindowsLog('Could not send graceful core shutdown: $error');
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 4));
    } catch (_) {
      try {
        await Process.run('taskkill.exe', ['/T', '/F', '/PID', process.pid.toString()])
            .timeout(const Duration(seconds: 1));
      } catch (_) {}
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
    if (identical(_windowsProcess, process)) _windowsProcess = null;
    try {
      await WindowsBrowserDialer.stop().timeout(const Duration(seconds: 1));
    } catch (error) {
      _appendWindowsLog('Browser Dialer shutdown exceeded its deadline: $error');
    }
    _emitWindowsState(VpnStatus.disconnected);
  }

  static Future<void> stop() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await _stopWindows();
      return;
    }
    await _methods.invokeMethod('stop');
  }

  /// Starts the setup wizard's Tor with [bridges]; returns its HTTP proxy port (SetupTor.kt).
  static Future<int> startSetupTor(List<String> bridges) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      throw UnsupportedError('Tor setup retry is not available on Windows yet.');
    }
    return await _methods.invokeMethod<int>('startSetupTor', {'bridges': bridges}) ?? 0;
  }

  /// The setup wizard's Tor: bootstrap progress (0-100), whether it runs, and why it stopped.
  static Future<({int progress, bool running, String? error})> setupTorStatus() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return (progress: 0, running: false, error: 'Tor setup retry is not available on Windows yet.');
    }
    final m = await _methods.invokeMapMethod<String, dynamic>('setupTorStatus') ?? const {};
    return (progress: (m['progress'] as int?) ?? 0, running: m['running'] == true, error: m['error'] as String?);
  }

  static Future<void> stopSetupTor() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) return Future.value();
    return _methods.invokeMethod('stopSetupTor');
  }

  /// Starts the local ECH gateway (networking/), used when Cloudflare can't be reached directly.
  static Future<void> startEchGateway() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      throw UnsupportedError('The ECH gateway is not available on Windows yet.');
    }
    return _methods.invokeMethod('startEchGateway');
  }

  /// Opens an HTTP(S) [url] in the default browser; false if it cannot be opened.
  static Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      return false;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await Process.start(
          'rundll32.exe',
          ['url.dll,FileProtocolHandler', uri.toString()],
          mode: ProcessStartMode.detached,
        );
        return true;
      } on ProcessException {
        return false;
      }
    }
    try {
      return await _methods.invokeMethod<bool>('openUrl', {'url': uri.toString()}) ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Domain Fronting's CA files (bpb-cert.crt / .key) are stored beside the Windows app,
  /// or in Android's private app storage.
  static String get _windowsMitmCaPath =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}bpb-cert';

  static Future<bool> mitmCaExists() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return await File('$_windowsMitmCaPath.crt').exists() &&
          await File('$_windowsMitmCaPath.key').exists();
    }
    return await _methods.invokeMethod<bool>('mitmCaExists') ?? false;
  }

  /// Whether this exact generated CA is trusted by the current Windows user.
  static Future<bool> mitmCaInstalled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;
    final certPath = '$_windowsMitmCaPath.crt';
    if (!await File(certPath).exists()) return false;
    final escapedPath = certPath.replaceAll("'", "''");
    final script = """
\$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('$escapedPath')
\$match = Get-ChildItem -Path 'Cert:\\CurrentUser\\Root' | Where-Object { \$_.Thumbprint -eq \$cert.Thumbprint } | Select-Object -First 1
if (\$match) { 'true' } else { 'false' }
""";
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-Command', script,
      ]);
      return result.exitCode == 0 &&
          result.stdout.toString().trim().toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveMitmCa(MitmCa ca) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final cert = File('$_windowsMitmCaPath.crt');
      final key = File('$_windowsMitmCaPath.key');
      await cert.writeAsString(ca.cert, flush: true);
      try {
        await key.writeAsString(ca.key, flush: true);
      } catch (_) {
        if (await cert.exists()) await cert.delete();
        rethrow;
      }
      return;
    }
    await _methods.invokeMethod('saveMitmCa', {'cert': ca.cert, 'key': ca.key});
  }

  /// Opens the generated public CA certificate in the Windows certificate viewer.
  static Future<void> openMitmCaCertificate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      throw StateError('Opening the certificate is supported on Windows only.');
    }
    final path = '$_windowsMitmCaPath.crt';
    if (!await File(path).exists()) throw StateError('Create the certificate first.');
    await Process.start(
      'rundll32.exe', ['url.dll,FileProtocolHandler', path],
      mode: ProcessStartMode.detached,
    );
  }

  /// Opens Android's CA install; on Android 11+ after saving bpb-cert.crt to Downloads,
  /// whose path it returns.
  static Future<String?> installMitmCa() => _methods.invokeMethod<String>('installMitmCa');

  /// Replaces Xray's geo files (geoip.dat, geosite.dat) with [files], each checked against its
  /// SHA-256 (hex) first: none is replaced unless all match. Xray uses them from its next start.
  static Future<void> saveGeoAssets(
    Map<String, ({Uint8List data, String sha256})> files,
  ) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      const allowed = {'geoip.dat', 'geosite.dat'};
      if (files.isEmpty || files.keys.any((name) => !allowed.contains(name))) {
        throw ArgumentError('Only geoip.dat and geosite.dat can be replaced.');
      }
      final digest = SHA256Digest();
      // Verify every file before touching the installed assets.
      for (final entry in files.entries) {
        final actual = digest.process(entry.value.data)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        if (actual != entry.value.sha256.toLowerCase()) {
          throw StateError('${entry.key} failed SHA-256 verification.');
        }
      }
      final directory = Directory(
        '${File(Platform.resolvedExecutable).parent.path}\\assets',
      );
      await directory.create(recursive: true);
      for (final entry in files.entries) {
        final target = File('${directory.path}\\${entry.key}');
        final temporary = File('${target.path}.tmp');
        final backup = File('${target.path}.bpb-backup');
        await temporary.writeAsBytes(entry.value.data, flush: true);
        if (await backup.exists()) await backup.delete();
        if (await target.exists()) await target.rename(backup.path);
        try {
          await temporary.rename(target.path);
          if (await backup.exists()) await backup.delete();
        } catch (_) {
          if (await backup.exists()) await backup.rename(target.path);
          rethrow;
        }
      }
      return;
    }
    await _methods.invokeMethod('saveGeoAssets', {
      'files': {
        for (final e in files.entries)
          e.key: {'data': e.value.data, 'sha256': e.value.sha256},
      },
    });
  }

  /// The cores' versions, from their own reports: Xray (e.g. 26.10.21) and
  /// the Psiphon (its core's module version) and Tor ("Tor version …") binaries; empty if unknown.
  static Future<({String xray, String psiphon, String tor})> versions() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final result = await _sendWindowsCommand({'command': 'versions'});
      return (
        xray: result['xray'] as String? ?? '',
        psiphon: result['psiphon'] as String? ?? '',
        tor: result['tor'] as String? ?? '',
      );
    }
    final m = await _methods.invokeMapMethod<String, String>('versions') ?? const {};
    return (xray: m['xray'] ?? '', psiphon: m['psiphon'] ?? '', tor: m['tor'] ?? '');
  }

  /// The installed app's version and, on Android, supported ABIs.
  static Future<({String version, List<String> abis})> appInfo() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      // Keep this in sync with the version field in pubspec.yaml until a desktop
      // release channel supplies package metadata.
      const version = String.fromEnvironment('BPB_APP_VERSION', defaultValue: '1.2.1');
      const build = String.fromEnvironment('BPB_BUILD_NUMBER', defaultValue: '');
      return (
        version: build.isEmpty ? version : '$version Build $build',
        abis: const <String>[],
      );
    }
    final m = await _methods.invokeMapMethod<String, dynamic>('appInfo') ?? const {};
    return (
      version: '${m['version'] ?? ''}',
      abis: (m['abis'] as List? ?? const []).map((e) => '$e').toList(),
    );
  }

  /// Whether the native Xray core is still running. Windows exposes this through
  /// the existing lightweight status command; other platforms keep their native
  /// state-event lifecycle and do not use this Windows-only poll.
  static Future<bool> isCoreRunning() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final result = await _sendWindowsCommand(
        {'command': 'status'},
        timeout: const Duration(seconds: 5),
      );
      return result['running'] == true;
    }
    return true;
  }

  /// Delay in ms through the running tunnel.
  static Future<int> measureDelay() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final result = await _sendWindowsCommand({'command': 'delay'});
      return (result['delay'] as num?)?.toInt() ?? -1;
    }
    final ms = await _methods.invokeMethod<int>('measureDelay');
    return ms ?? -1;
  }

  /// Proxied traffic: bytes in the last second and since connecting, sampled by the
  /// VPN service (which also shows proxy and direct rates in its notification).
  static Future<({int up, int down, int totalUp, int totalDown})> traffic() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final result = await _sendWindowsCommand({'command': 'traffic'});
      var up = 0;
      var down = 0;
      for (final item in (result['traffic'] as String? ?? '').split(';')) {
        final fields = item.split(',');
        if (fields.length != 3) continue;
        final bytes = int.tryParse(fields[2]) ?? 0;
        if (fields[1] == 'uplink') up += bytes;
        if (fields[1] == 'downlink') down += bytes;
      }
      return (up: up, down: down, totalUp: up, totalDown: down);
    }
    final m = await _methods.invokeMapMethod<String, int>('trafficStats');
    return (
      up: m?['proxyUp'] ?? 0,
      down: m?['proxyDown'] ?? 0,
      totalUp: m?['proxyUpTotal'] ?? 0,
      totalDown: m?['proxyDownTotal'] ?? 0,
    );
  }

  static Future<List<InstalledApp>> installedApps() async {
    final list = await _methods.invokeListMethod<Map>('installedApps') ?? const [];
    return list
        .map(
          (m) => InstalledApp(
            m['package'] as String,
            m['label'] as String,
            m['system'] as bool? ?? false,
            m['icon'] as Uint8List?,
          ),
        )
        .toList();
  }
}
