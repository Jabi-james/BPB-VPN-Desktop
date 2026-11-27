import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class V2rayProfile {
  final String id, name, address, protocol, raw, subscriptionId;
  const V2rayProfile({required this.id, required this.name, required this.address, required this.protocol, required this.raw, this.subscriptionId = ''});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'address': address, 'protocol': protocol, 'raw': raw, 'subscriptionId': subscriptionId};
  factory V2rayProfile.fromJson(Map value) => V2rayProfile(
    id: value['id']?.toString() ?? '', name: value['name']?.toString() ?? 'Unnamed',
    address: value['address']?.toString() ?? '', protocol: value['protocol']?.toString() ?? 'Unknown',
    raw: value['raw']?.toString() ?? '', subscriptionId: value['subscriptionId']?.toString() ?? '');
}

class V2raySubscription {
  final String id, name, url;
  const V2raySubscription({required this.id, required this.name, required this.url});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};
  factory V2raySubscription.fromJson(Map value) => V2raySubscription(
    id: value['id']?.toString() ?? '', name: value['name']?.toString() ?? '',
    url: value['url']?.toString() ?? '');
}

class V2rayStore {
  static const _subsKey = 'v2ray.subscriptions.v2';
  static const _profilesKey = 'v2ray.profiles.v2';
  static const _dnsKey = 'v2ray.dns.v1';
  static Future<List<V2raySubscription>> subscriptions() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_subsKey);
    if (raw == null) return [];
    try { return (jsonDecode(raw) as List).whereType<Map>().map(V2raySubscription.fromJson).where((e) => e.id.isNotEmpty).toList(); } catch (_) { return []; }
  }
  static Future<List<V2rayProfile>> profiles() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_profilesKey);
    if (raw == null) return [];
    try { return (jsonDecode(raw) as List).whereType<Map>().map(V2rayProfile.fromJson).where((e) => e.id.isNotEmpty).toList(); } catch (_) { return []; }
  }
  static Future<void> saveSubscriptions(List<V2raySubscription> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_subsKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
  static Future<void> saveProfiles(List<V2rayProfile> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_profilesKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
  static Future<Map<String, String>> dns() async {
    final p = await SharedPreferences.getInstance();
    return {'remote': p.getString('$_dnsKey.remote') ?? '1.1.1.1', 'local': p.getString('$_dnsKey.local') ?? 'localhost'};
  }
  static Future<void> saveDns(String remote, String local) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_dnsKey.remote', remote);
    await p.setString('$_dnsKey.local', local);
  }
  static String _decodeBase64(String value) {
    var s = value.trim().replaceAll('-', '+').replaceAll('_', '/');
    s = s.padRight(s.length + ((4 - s.length % 4) % 4), '=');
    return utf8.decode(base64.decode(s), allowMalformed: true);
  }
  static List<V2rayProfile> parseLinks(String input, {String subscriptionId = ''}) {
    var text = input.trim();
    if (text.isEmpty) return [];
    if (!text.contains('://') || (!text.startsWith('vless://') && !text.startsWith('vmess://') && !text.startsWith('trojan://') && !text.startsWith('ss://'))) {
      try { final decoded = _decodeBase64(text); if (decoded.contains('://')) text = decoded; } catch (_) {}
    }
    final result = <V2rayProfile>[];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final raw = line.trim();
      if (raw.isEmpty) continue;
      try {
        String protocol, address = '', name = '';
        if (raw.startsWith('vmess://')) {
          final payload = _decodeBase64(raw.substring(8));
          final data = jsonDecode(payload);
          if (data is! Map) continue;
          protocol = 'VMess'; address = data['add']?.toString() ?? ''; name = data['ps']?.toString() ?? '';
        } else if (raw.startsWith('vless://')) {
          protocol = 'VLESS'; final uri = Uri.parse(raw); address = uri.host; name = uri.fragment;
        } else if (raw.startsWith('trojan://')) {
          protocol = 'Trojan'; final uri = Uri.parse(raw); address = uri.host; name = uri.fragment;
        } else if (raw.startsWith('ss://')) {
          protocol = 'Shadowsocks'; final uri = Uri.parse(raw); address = uri.host; name = uri.fragment;
          if (address.isEmpty) { final body = raw.substring(5).split('#').first; final decoded = _decodeBase64(body); address = decoded.split('@').last.split(':').first; }
        } else { continue; }
        result.add(V2rayProfile(id: DateTime.now().microsecondsSinceEpoch.toString() + result.length.toString(),
          name: Uri.decodeComponent(name.isEmpty ? '$protocol · $address' : name), address: address, protocol: protocol, raw: raw, subscriptionId: subscriptionId));
      } catch (_) { continue; }
    }
    return result;
  }
}
