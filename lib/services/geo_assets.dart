import 'dart:typed_data';

import 'package:http/http.dart' as http;

class GeoAssetsException implements Exception {
  final String message;
  const GeoAssetsException(this.message);

  @override
  String toString() => message;
}

/// Downloads a matched geoip.dat / geosite.dat pair for the selected country.
/// Every source publishes SHA-256 sidecars; the app verifies both files before replacing assets.
class GeoAssetsDownloader {
  static const files = ['geoip.dat', 'geosite.dat'];

  static const sources = <String, String>{
    'iran': 'https://github.com/Chocolate4U/Iran-v2ray-rules/releases/latest/download',
    'china': 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download',
    'russia': 'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release',
  };

  final http.Client client;
  const GeoAssetsDownloader(this.client);

  /// Each file's content and its SHA-256 (hex), by name.
  Future<Map<String, ({Uint8List data, String sha256})>> download({
    required String country,
    void Function(String file, int received, int? total)? onProgress,
  }) async {
    final base = sources[country];
    if (base == null) throw GeoAssetsException('Unsupported Geo country: $country');
    final downloaded = <String, ({Uint8List data, String sha256})>{};
    for (final name in files) {
      final sha256 = _hash(await _get('$base/$name.sha256sum'), name);
      downloaded[name] = (
        data: await _getFile('$base/$name', name, onProgress),
        sha256: sha256,
      );
    }
    return downloaded;
  }

  Future<Uint8List> _get(String url) async {
    final http.Response res;
    try {
      res = await client.get(Uri.parse(url)).timeout(const Duration(minutes: 3));
    } catch (e) {
      throw GeoAssetsException("Can't reach GitHub: $e");
    }
    if (res.statusCode != 200) {
      throw GeoAssetsException('GitHub answered HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  Future<Uint8List> _getFile(
    String url,
    String name,
    void Function(String file, int received, int? total)? onProgress,
  ) async {
    final http.StreamedResponse response;
    try {
      response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(minutes: 3));
    } catch (e) {
      throw GeoAssetsException("Can't reach GitHub: $e");
    }
    if (response.statusCode != 200) {
      throw GeoAssetsException('GitHub answered HTTP ${response.statusCode}');
    }

    final total = response.contentLength;
    var received = 0;
    final bytes = BytesBuilder(copy: false);
    onProgress?.call(name, received, total);
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(minutes: 3),
      )) {
        bytes.add(chunk);
        received += chunk.length;
        onProgress?.call(name, received, total);
      }
    } catch (e) {
      throw GeoAssetsException('Download of $name failed: $e');
    }
    return bytes.takeBytes();
  }

  /// The hash in a sha256sum line (`<hex>  <file>`).
  static String _hash(Uint8List sum, String name) {
    final hash = String.fromCharCodes(sum).trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) throw GeoAssetsException('Unexpected checksum for $name');
    return hash;
  }
}
