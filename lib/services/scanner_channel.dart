import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ScanProtocol { vless, warp, masqueH2, masqueH3 }

extension ScanProtocolLabels on ScanProtocol {
  String get label => switch (this) {
    ScanProtocol.vless => 'VLESS · HTTP/1.1',
    ScanProtocol.warp => 'WARP · WireGuard',
    ScanProtocol.masqueH2 => 'MASQUE · HTTP/2',
    ScanProtocol.masqueH3 => 'MASQUE · HTTP/3',
  };

  String get wireName => switch (this) {
    ScanProtocol.vless => 'vless',
    ScanProtocol.warp => 'warp',
    ScanProtocol.masqueH2 => 'masque-h2',
    ScanProtocol.masqueH3 => 'masque-h3',
  };

  bool get isMasque =>
      this == ScanProtocol.masqueH2 || this == ScanProtocol.masqueH3;
  bool get isWarpLike => this != ScanProtocol.vless;
}

class ScanResult {
  final String ip;
  final double httpMillis;

  const ScanResult({required this.ip, required this.httpMillis});

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
    ip: json['ip'] as String,
    httpMillis: (json['httpMillis'] as num).toDouble(),
  );
}

class ScannerEvent {
  final String type;
  final String? phase;
  final int? completed;
  final int? total;
  final List<ScanResult> results;
  final String? message;

  const ScannerEvent({
    required this.type,
    this.phase,
    this.completed,
    this.total,
    this.results = const [],
    this.message,
  });

  factory ScannerEvent.fromJson(Map<String, dynamic> json) => ScannerEvent(
    type: json['type'] as String,
    phase: json['phase'] as String?,
    completed: (json['completed'] as num?)?.toInt(),
    total: (json['total'] as num?)?.toInt(),
    results: (json['results'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ScanResult.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    message: json['message'] as String?,
  );
}

class ScannerChannel {
  static const _methods = MethodChannel('bpb/core');
  static const _events = EventChannel('bpb/scanner');
  static Process? _desktopProcess;
  static final StreamController<ScannerEvent> _desktopEvents =
      StreamController<ScannerEvent>.broadcast();
  static final Map<String, Completer<void>> _pending = {};
  static int _nextCommandId = 0;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || _isDesktop);

  static Stream<ScannerEvent> get events {
    if (_isDesktop) return _desktopEvents.stream;
    return _events.receiveBroadcastStream().map(
      (event) => ScannerEvent.fromJson(
        Map<String, dynamic>.from(jsonDecode(event as String) as Map),
      ),
    );
  }

  static Future<void> start(Map<String, dynamic> options) async {
    _requirePlatform();
    if (_isDesktop) {
      await _ensureDesktopProcess();
      await _sendDesktop('start', options: options);
      return;
    }
    final error = await _methods.invokeMethod<String>('scannerStart', {
      'config': jsonEncode(options),
    });
    if (error != null && error.isNotEmpty) throw StateError(error);
  }

  static Future<void> pause() => _call('pause', 'scannerPause');
  static Future<void> resume() => _call('resume', 'scannerResume');
  static Future<void> stop() => _call('stop', 'scannerStop');

  static Future<void> _call(String desktopAction, String androidMethod) async {
    _requirePlatform();
    if (_isDesktop) {
      await _sendDesktop(desktopAction);
      return;
    }
    final error = await _methods.invokeMethod<String>(androidMethod);
    if (error != null && error.isNotEmpty) throw StateError(error);
  }

  static Future<void> _ensureDesktopProcess() async {
    if (_desktopProcess != null) return;
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final executable = Platform.isWindows
        ? '${executableDir}\\bpb_scanner.exe'
        : '${executableDir}/bpb_scanner';
    if (!await File(executable).exists()) {
      throw StateError('BPB scanner helper was not found: $executable');
    }
    final process = await Process.start(executable, const []);
    _desktopProcess = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleDesktopLine);
    process.stderr.transform(utf8.decoder).listen(
      (message) => debugPrint('BPB scanner: $message'),
    );
    process.exitCode.then((code) {
      if (identical(_desktopProcess, process)) _desktopProcess = null;
      final error = StateError('BPB scanner process exited (code $code).');
      for (final completer in _pending.values) {
        if (!completer.isCompleted) completer.completeError(error);
      }
      _pending.clear();
    });
  }

  static Future<void> _sendDesktop(
    String action, {
    Map<String, dynamic>? options,
  }) async {
    final process = _desktopProcess;
    if (process == null) throw StateError('BPB scanner process is not running.');
    final id = (++_nextCommandId).toString();
    final completer = Completer<void>();
    _pending[id] = completer;
    process.stdin.writeln(jsonEncode({
      'id': id,
      'action': action,
      'options': ?options,
    }));
    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      _pending.remove(id);
    }
  }

  static void _handleDesktopLine(String line) {
    try {
      final json = Map<String, dynamic>.from(jsonDecode(line) as Map);
      final type = json['type'] as String?;
      final id = json['id'] as String?;
      if ((type == 'ack' || type == 'error') && id != null) {
        final completer = _pending[id];
        if (completer != null && !completer.isCompleted) {
          if (type == 'error') {
            completer.completeError(
              StateError(json['message'] as String? ?? 'Scanner error'),
            );
          } else {
            completer.complete();
          }
          return;
        }
      }
      if (type == 'progress' ||
          type == 'done' ||
          type == 'stopped' ||
          type == 'error') {
        _desktopEvents.add(ScannerEvent.fromJson(json));
      }
    } catch (error) {
      debugPrint('Invalid BPB scanner event: $error');
    }
  }

  static void _requirePlatform() {
    if (!isSupported) {
      throw UnsupportedError(
        'Cloudflare scanning is available on Android, Windows and Linux.',
      );
    }
  }
}

class ScannerAssets {
  static const warpPorts = [
    443,
    500,
    854,
    859,
    864,
    878,
    880,
    890,
    891,
    894,
    903,
    908,
    928,
    934,
    939,
    942,
    943,
    945,
    946,
    955,
    968,
    987,
    988,
    1002,
    1010,
    1014,
    1018,
    1070,
    1074,
    1180,
    1387,
    1701,
    1843,
    2371,
    2408,
    2506,
    3138,
    3476,
    3581,
    3854,
    4177,
    4198,
    4233,
    4443,
    4500,
    5279,
    5956,
    7103,
    7152,
    7156,
    7281,
    7559,
    8095,
    8319,
    8443,
    8742,
    8854,
    8886,
  ];

  static Future<List<String>> loadCidrs({required bool warpLike}) async {
    final raw = await rootBundle.loadString(
      warpLike
          ? 'assets/scanner/warp-cidrs.txt'
          : 'assets/scanner/vless-cidrs.txt',
    );
    final cidrs = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toSet()
        .toList();
    if (cidrs.isEmpty) {
      throw StateError('The bundled scanner CIDR list is empty.');
    }
    return cidrs;
  }
}
