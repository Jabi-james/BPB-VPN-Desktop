import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'ech_client.dart';
import 'my_ip.dart';
import 'vpn_channel.dart';

typedef CloudflareRoute = Future<http.Client?> Function();

/// The HTTP client of every Cloudflare API call (api.cloudflare.com, WARP and MASQUE
/// registration): [CloudflareApi], [WarpRegistrar] and [MasqueRegistrar] use it by default, so
/// callers never choose a route. Each request goes
///
///  1. directly;
///  2. through the running tunnel, when connected;
///  3. through the local ECH gateway, pinned to IPs resolved through independent DoH resolvers
///     when ordinary DNS / routes cannot reach the Cloudflare API.
///
/// An HTTP response of any status, even an error, ends route selection. Only transport failures
/// trigger another route. When every route fails, the first error (the direct one) is thrown.
///
/// [viaTor] (the setup wizard's Tor retry) replaces all of that with Tor alone.
class CloudflareClient extends http.BaseClient {
  /// The tunnel's local proxy port while connected, else null; set by [AppState].
  static int? Function()? tunnelPort;

  static final _torKey = Object();

  /// Runs [body] with every Cloudflare request made in it going through the HTTP proxy on
  /// [port] only (Tor): no direct, tunnel or ECH route.
  static Future<T> viaTor<T>(int port, Future<T> Function() body) =>
      runZoned(body, zoneValues: {_torKey: port});

  static Future<void>? _gateway;

  static Future<void> _startGateway() => _gateway ??= () async {
    try {
      await VpnChannel.startEchGateway();
    } catch (_) {
      _gateway = null;
      rethrow;
    }
  }();

  /// The routes are [routes] for tests, else direct and the running tunnel. ECH is handled
  /// after these so it can try every freshly resolved IP while preserving the original host.
  CloudflareClient({this.routes});

  final List<CloudflareRoute>? routes;
  final _owned = <http.Client>[];
  http.Client? _direct, _tunnel, _tor;

  http.Client _own(http.Client client) {
    _owned.add(client);
    return client;
  }

  late final List<CloudflareRoute> _defaultRoutes = [
    () async => _direct ??= _own(
      proxiedClient(null, connectTimeout: const Duration(seconds: 8)),
    ),
    () async {
      final port = tunnelPort?.call();
      return port == null ? null : _tunnel ??= _own(proxiedClient(port));
    },
  ];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // A request can be sent once; keep its body to send copies.
    final body = await request.finalize().toBytes();
    http.Request copy() => http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;

    final tor = Zone.current[_torKey] as int?;
    final chain = tor != null
        ? <CloudflareRoute>[() async => _tor ??= _own(proxiedClient(tor))]
        : (routes ?? _defaultRoutes);

    Object? first;
    StackTrace? firstStack;
    for (final route in chain) {
      try {
        final client = await route();
        if (client == null) continue;
        return await client.send(copy());
      } catch (e, st) {
        if (!_isTransportError(e)) {
          if (first == null) rethrow;
          break;
        }
        if (first == null) {
          first = e;
          firstStack = st;
        }
      }
    }

    // Custom routes and Tor are intentionally isolated from this default fallback.
    if (tor == null && routes == null) {
      try {
        await _startGateway();
        final host = request.url.host;
        final resolved = await _CloudflareIpResolver.resolve(host);
        final candidates = <String>{
          ...resolved,
          ?_fallbackDial[host],
        };
        for (final ip in candidates) {
          final dialAddress = ip.contains(':') ? '[$ip]:443' : '$ip:443';
          final client = _own(EchClient(dial: {host: dialAddress}));
          try {
            return await client.send(copy());
          } catch (e, st) {
            if (!_isTransportError(e)) {
              if (first == null) rethrow;
              break;
            }
            if (first == null) {
              first = e;
              firstStack = st;
            }
          }
        }
      } catch (e, st) {
        if (!_isTransportError(e)) {
          if (first == null) rethrow;
        } else if (first == null) {
          first = e;
          firstStack = st;
        }
      }
    }

    if (first == null) {
      throw http.ClientException('No Cloudflare network route is available.', request.url);
    }
    Error.throwWithStackTrace(first, firstStack!);
  }

  /// Last-resort compatibility addresses, used only when online DNS resolution returns no IPs.
  /// These are not treated as an authoritative list and are never preferred over live DNS.
  static const _fallbackDial = {
    'api.cloudflareclient.com': '188.114.96.0',
    'api.cloudflare.com': '188.114.97.0',
  };

  /// The server couldn't be reached (blocked, timed out, reset), rather than answering.
  static bool _isTransportError(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is TlsException ||
      e is HttpException ||
      e is http.ClientException;

  @override
  void close() {
    for (final client in _owned) {
      client.close();
    }
  }
}

/// Resolves Cloudflare API hosts over HTTPS using independent public DNS resolvers.
/// Resolver connections are pinned to their published anycast IPs, so this lookup does not
/// depend on the system DNS path that may have been filtered. The original API host is still
/// used by EchClient for HTTP Host and TLS SNI.
class _CloudflareIpResolver {
  static const _resolvers = [
    (host: 'dns.google', ip: '8.8.8.8'),
    (host: 'dns.google', ip: '8.8.4.4'),
    (host: 'cloudflare-dns.com', ip: '1.1.1.1'),
    (host: 'cloudflare-dns.com', ip: '1.0.0.1'),
  ];

  static final Map<String, ({List<String> addresses, DateTime expiresAt})> _cache = {};

  static Future<List<String>> resolve(String host) async {
    final cached = _cache[host];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.addresses;
    }

    final addresses = <String>{};
    var ttl = 3600;
    for (final resolver in _resolvers) {
      final result = await _queryResolver(resolver, host);
      for (final answer in result) {
        addresses.add(answer.address);
        if (answer.ttl > 0 && answer.ttl < ttl) ttl = answer.ttl;
      }
      if (addresses.isNotEmpty) break;
    }

    final values = addresses.toList();
    if (values.isNotEmpty) {
      _cache[host] = (
        addresses: values,
        expiresAt: DateTime.now().add(Duration(seconds: ttl.clamp(60, 3600).toInt())),
      );
    }
    return values;
  }

  static Future<List<({String address, int ttl})>> _queryResolver(
    ({String host, String ip}) resolver,
    String name,
  ) async {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..connectionFactory = (uri, proxyHost, proxyPort) {
        if (uri.host != resolver.host || proxyHost != null) {
          throw const SocketException('Unexpected DNS resolver connection target.');
        }
        return Socket.startConnect(resolver.ip, 443);
      };
    final client = IOClient(httpClient);
    final answers = <({String address, int ttl})>[];
    try {
      for (final type in const ['A', 'AAAA']) {
        try {
          final uri = Uri.https(resolver.host, '/resolve', {'name': name, 'type': type});
          final response = await client.get(
            uri,
            headers: const {'accept': 'application/dns-json'},
          ).timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) continue;
          final payload = jsonDecode(response.body);
          if (payload is! Map || payload['Status'] != 0 || payload['Answer'] is! List) {
            continue;
          }
          final expectedType = type == 'A' ? 1 : 28;
          for (final raw in payload['Answer'] as List) {
            if (raw is! Map || raw['type'] != expectedType || raw['data'] is! String) {
              continue;
            }
            final value = raw['data'] as String;
            final address = InternetAddress.tryParse(value);
            if (address == null ||
                address.isLoopback ||
                address.isLinkLocal ||
                address.isMulticast ||
                address.rawAddress.every((byte) => byte == 0)) {
              continue;
            }
            final recordTtl = raw['TTL'] is num ? (raw['TTL'] as num).toInt() : 300;
            answers.add((address: address.address, ttl: recordTtl));
          }
        } catch (_) {
          // Try the other record type and, if necessary, the next independent resolver.
        }
      }
    } finally {
      client.close();
    }
    return answers;
  }
}
