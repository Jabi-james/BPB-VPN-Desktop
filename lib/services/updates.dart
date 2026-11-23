import 'dart:convert';

import 'package:http/http.dart' as http;

/// A newer release on GitHub (see [UpdateChecker]).
class AppUpdate {
  final String version;
  final String notes;
  final String pageUrl;
  final String? apkUrl;

  const AppUpdate({required this.version, required this.notes, required this.pageUrl, this.apkUrl});
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);

  @override
  String toString() => message;
}

class UpdateChecker {
  static const repository = 'bia-pain-bache/BPB-VPN';
  static const _latest = 'https://api.github.com/repos/$repository/releases/latest';
  static const desktopRepository = 'NottDevv/BPB-VPN-Desktop';
  static const _desktopLatest = 'https://api.github.com/repos/$desktopRepository/releases/latest';

  final http.Client client;
  const UpdateChecker(this.client);

  Future<Map<String, dynamic>> _latestRelease(String url) async {
    final http.Response res;
    try {
      res = await client.get(
        Uri.parse(url),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw UpdateException("Can't reach GitHub: $e");
    }
    if (res.statusCode == 404) {
      throw const UpdateException(
        'GitHub returned 404. The repository may be private or have no published release; update status is unknown.',
      );
    }
    if (res.statusCode != 200) {
      throw UpdateException('GitHub answered HTTP ${res.statusCode}');
    }
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const UpdateException('Unexpected answer from GitHub');
    }
  }

  Future<AppUpdate?> check({required String installed, required List<String> abis}) async {
    final json = await _latestRelease(_latest);
    final version = '${json['tag_name'] ?? ''}'.replaceFirst(RegExp('^v'), '');
    if (compareVersions(version, installed) <= 0) return null;
    final assets = (json['assets'] as List? ?? const []).whereType<Map>();
    String? apkUrl;
    for (final abi in abis) {
      apkUrl = assets
          .where((a) => '${a['name']}'.endsWith('-$abi.apk'))
          .map((a) => '${a['browser_download_url']}')
          .firstOrNull;
      if (apkUrl != null) break;
    }
    return AppUpdate(
      version: version,
      notes: '${json['body'] ?? ''}'.trim(),
      pageUrl: '${json['html_url'] ?? 'https://github.com/$repository/releases'}',
      apkUrl: apkUrl,
    );
  }

  /// Windows: compares both semantic version and build number, then selects the installer.
  Future<AppUpdate?> checkDesktop({required String installed}) async {
    final json = await _latestRelease(_desktopLatest);
    final latest = parseDesktopVersion('${json['tag_name'] ?? ''}');
    final current = parseDesktopVersion(installed);
    if (latest == null || current == null) {
      throw const UpdateException('The installed or published desktop version has an unsupported format.');
    }
    final comparison = compareVersions(latest.version, current.version);
    final isNewer = comparison > 0 || (comparison == 0 && latest.build > current.build);
    if (!isNewer) return null;

    final assets = (json['assets'] as List? ?? const []).whereType<Map>();
    final installer = assets
        .where((a) => a['name'] == 'bpb-vpn-windows-x64-installer.exe')
        .map((a) => '${a['browser_download_url']}')
        .firstOrNull;
    if (installer == null || installer.isEmpty || installer == 'null') {
      throw const UpdateException(
        'A newer desktop release exists, but its Windows installer is not attached yet.',
      );
    }
    return AppUpdate(
      version: '${latest.version} Build ${latest.build}',
      notes: _shortReleaseNotes('${json['body'] ?? ''}'),
      pageUrl: '${json['html_url'] ?? 'https://github.com/$desktopRepository/releases'}',
      apkUrl: installer,
    );
  }

  /// Accepts tags such as v1.2.2-build.353 and installed strings such as 1.2.2 Build 353.
  static ({String version, int build})? parseDesktopVersion(String value) {
    final match = RegExp(
      r'^v?(\d+\.\d+\.\d+)(?:[- ]build[. ]?(\d+))?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    return (version: match.group(1)!, build: int.tryParse(match.group(2) ?? '') ?? 0);
  }

  static String _shortReleaseNotes(String body) {
    final lines = body.split(RegExp(r'\r?\n'));
    var inNotes = false;
    final bullets = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (RegExp(r'^#{1,6}\s*(what.?s changed|release notes)\s*$', caseSensitive: false).hasMatch(line)) {
        inNotes = true;
        continue;
      }
      if (inNotes && RegExp(r'^#{1,6}\s+').hasMatch(line)) break;
      if (!inNotes || !RegExp(r'^[-*]\s+').hasMatch(line)) continue;
      var item = line.replaceFirst(RegExp(r'^[-*]\s+'), '');
      item = item.replaceAll(RegExp(r'[\x60*_]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (item.isEmpty) continue;
      if (item.length > 112) item = item.substring(0, 109).trimRight() + '…';
      bullets.add(item);
      if (bullets.length == 3) break;
    }
    return bullets.map((item) => '• ' + item).join('\n');
  }
}

/// Compares "X.Y.Z" versions numerically (missing or non-numeric parts count as 0); anything
/// after a "+" or "-" (build number, pre-release) is ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[+-]')).first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
