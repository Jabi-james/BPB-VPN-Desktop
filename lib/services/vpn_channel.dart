import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  static Completer<Map<String, dynamic>>? _windowsPending;
  static final _windowsStates = StreamController<VpnStateEvent>.broadcast();
  static DateTime? _windowsConnectedAt;
  static final List<String> _windowsLogLines = [];
  static const int _windowsMaxLogLines = 2000;

  static void _appendWindowsLog(String line) {
    if (line.isEmpty) return;
    _windowsLogLines.add(line);
    if (_windowsLogLines.length > _windowsMaxLogLines) {
      _windowsLogLines.removeRange(0, _windowsLogLines.length - _windowsMaxLogLines);
    }
  }

  static void _emitWindowsState(VpnStatus status, [String? error]) {
    _windowsStates.add(VpnStateEvent(
      status, error,
      status == VpnStatus.connected ? (_windowsConnectedAt ??= DateTime.now()) : null,
      null,
    ));
    if (status == VpnStatus.disconnected) _windowsConnectedAt = null;
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
    Map<String, dynamic> request,
  ) async {
    await _ensureWindowsProcess();
    final process = _windowsProcess!;
    if (_windowsPending != null) {
      throw StateError('Another BPB core command is still running.');
    }
    final completer = Completer<Map<String, dynamic>>();
    _windowsPending = completer;
    try {
      process.stdin.writeln(jsonEncode(request));
      await process.stdin.flush();
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      if (identical(_windowsPending, completer)) _windowsPending = null;
    }
  }

  static Future<void> _startWindows({
    required Map<String, dynamic> config,
    required String appMode,
  }) async {
    _emitWindowsState(VpnStatus.connecting);
    try {
      final result = await _sendWindowsCommand({
        'command': 'start', 'mode': appMode, 'config': jsonEncode(config),
      });
      if (result['ok'] != true) {
        throw StateError(result['error'] as String? ?? 'BPB core failed to start.');
      }
      _emitWindowsState(VpnStatus.connected);
    } catch (error) {
      _emitWindowsState(VpnStatus.disconnected, '$error');
      rethrow;
    }
  }

  static Future<void> _stopWindows() async {
    if (_windowsProcess == null) {
      _emitWindowsState(VpnStatus.disconnected);
      return;
    }
    _emitWindowsState(VpnStatus.disconnecting);
    try {
      final result = await _sendWindowsCommand({'command': 'stop'});
      if (result['ok'] != true) {
        throw StateError(result['error'] as String? ?? 'BPB core failed to stop.');
      }
      _emitWindowsState(VpnStatus.disconnected);
    } catch (error) {
      _emitWindowsState(VpnStatus.disconnected, '$error');
      rethrow;
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
    Map<String, dynamic>? psiphonConfig,
    bool browserDialer = false,
    bool verifyConnection = false,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await _startWindows(config: config, appMode: appMode);
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
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'DNS server testing is currently available on Android only.',
      );
    }
    final raw = await _methods.invokeMethod<String>(
      'checkDns',
      jsonEncode(request),
    );
    if (raw == null) throw StateError('DNS test returned no result.');
    final response = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final ok = response['ok'] == true;
    final latency = response['latency'];
    return (ok: ok, latency: ok && latency is num ? latency.toDouble() : null);
  }

  /// The end of Xray's log for the current/last connection.
  static Future<String> readLog({String log = 'xray'}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      if (log != 'xray') return '';
      return _windowsLogLines.join('\n');
    }
    return await _methods.invokeMethod<String>('readLog', {'log': log}) ?? '';
  }

  /// Bytes in each log ("xray", "tor", "psiphon") since the last connect.
  static Future<Map<String, int>> logSizes() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return {'xray': utf8.encode(_windowsLogLines.join('\n')).length};
    }
    return (await _methods.invokeMapMethod<String, int>('logSizes')) ?? const {};
  }

  static Future<void> clearLog() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _windowsLogLines.clear();
      return;
    }
    await _methods.invokeMethod('clearLog');
  }

  /// Saves [content] as [name] and opens the share sheet so the user picks an app.
  static Future<void> shareFile({required String name, required String content, String title = 'Share'}) =>
      _methods.invokeMethod('shareFile', {'name': name, 'content': content, 'title': title});

  /// Saves [content] as [name] in Downloads (Android 7-9: a Save-as screen). Returns where
  /// it was saved, or null if the user cancelled.
  static Future<String?> saveFile({required String name, required String content}) =>
      _methods.invokeMethod<String>('saveFile', {'name': name, 'content': content});

  /// Opens the system file picker and returns the chosen file's name and text, or null if cancelled.
  static Future<({String name, String content})?> pickFile() async {
    final file = await _methods.invokeMapMethod<String, String>('pickFile');
    if (file == null) return null;
    return (name: file['name'] ?? '', content: file['content'] ?? '');
  }

  static Future<void> stop() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await _stopWindows();
      return;
    }
    await _methods.invokeMethod('stop');
  }

  /// Starts the setup wizard's Tor with [bridges]; returns its HTTP proxy port (SetupTor.kt).
  static Future<int> startSetupTor(List<String> bridges) async =>
      await _methods.invokeMethod<int>('startSetupTor', {'bridges': bridges}) ?? 0;

  /// The setup wizard's Tor: bootstrap progress (0-100), whether it runs, and why it stopped.
  static Future<({int progress, bool running, String? error})> setupTorStatus() async {
    final m = await _methods.invokeMapMethod<String, dynamic>('setupTorStatus') ?? const {};
    return (progress: (m['progress'] as int?) ?? 0, running: m['running'] == true, error: m['error'] as String?);
  }

  static Future<void> stopSetupTor() => _methods.invokeMethod('stopSetupTor');

  /// Starts the local ECH gateway (networking/), used when Cloudflare can't be reached directly.
  static Future<void> startEchGateway() => _methods.invokeMethod('startEchGateway');

  /// Opens [url] in the browser; false if nothing could handle it.
  static Future<bool> openUrl(String url) async {
    try {
      return await _methods.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Domain Fronting's CA files (bpb-cert.crt / .key) are in the app's storage.
  static Future<bool> mitmCaExists() async => await _methods.invokeMethod<bool>('mitmCaExists') ?? false;

  static Future<void> saveMitmCa(MitmCa ca) => _methods.invokeMethod('saveMitmCa', {'cert': ca.cert, 'key': ca.key});

  /// Opens Android's CA install; on Android 11+ after saving bpb-cert.crt to Downloads,
  /// whose path it returns.
  static Future<String?> installMitmCa() => _methods.invokeMethod<String>('installMitmCa');

  /// Replaces Xray's geo files (geoip.dat, geosite.dat) with [files], each checked against its
  /// SHA-256 (hex) first: none is replaced unless all match. Xray uses them from its next start.
  static Future<void> saveGeoAssets(Map<String, ({Uint8List data, String sha256})> files) =>
      _methods.invokeMethod('saveGeoAssets', {
        'files': {
          for (final e in files.entries) e.key: {'data': e.value.data, 'sha256': e.value.sha256},
        },
      });

  /// The cores' versions, from their own reports: Xray (e.g. 26.10.21) and
  /// the Psiphon (its core's module version) and Tor ("Tor version …") binaries; empty if unknown.
  static Future<({String xray, String psiphon, String tor})> versions() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final result = await _sendWindowsCommand({'command': 'versions'});
      return (
        xray: result['xray'] as String? ?? '',
        psiphon: '',
        tor: '',
      );
    }
    final m = await _methods.invokeMapMethod<String, String>('versions') ?? const {};
    return (xray: m['xray'] ?? '', psiphon: m['psiphon'] ?? '', tor: m['tor'] ?? '');
  }

  /// The installed app's version (from pubspec.yaml) and the phone's ABIs, preferred first.
  static Future<({String version, List<String> abis})> appInfo() async {
    final m = await _methods.invokeMapMethod<String, dynamic>('appInfo') ?? const {};
    return (
      version: '${m['version'] ?? ''}',
      abis: (m['abis'] as List? ?? const []).map((e) => '$e').toList(),
    );
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
