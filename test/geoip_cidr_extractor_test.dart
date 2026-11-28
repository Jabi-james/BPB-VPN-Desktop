import 'dart:convert';
import 'dart:typed_data';

import 'package:bpb/services/geoip_cidr_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> varint(int value) {
  final bytes = <int>[];
  while (value > 0x7f) {
    bytes.add((value & 0x7f) | 0x80);
    value >>= 7;
  }
  bytes.add(value);
  return bytes;
}

List<int> fieldBytes(int number, List<int> value) => [
  ...varint((number << 3) | 2),
  ...varint(value.length),
  ...value,
];

List<int> fieldVarint(int number, int value) => [
  ...varint(number << 3),
  ...varint(value),
];

List<int> cidr(List<int> address, int prefix) => [
  ...fieldBytes(1, address),
  ...fieldVarint(2, prefix),
];

List<int> geoIp(String tag, List<List<int>> entries) => [
  ...fieldBytes(1, utf8.encode(tag)),
  for (final entry in entries) ...fieldBytes(2, entry),
];

void main() {
  test('extracts and normalizes IPv4 and IPv6 Cloudflare CIDRs only', () {
    final ipv4 = cidr([203, 0, 113, 42], 24);
    final ipv6 = cidr([
      0x20, 0x01, 0x0d, 0xb8, 0xab, 0xcd, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 1,
    ], 32);
    final other = geoIp('private', [cidr([10, 0, 0, 1], 8)]);
    final cloudflare = geoIp('Cloudflare', [ipv6, ipv4, ipv4]);
    final asset = Uint8List.fromList([
      ...fieldBytes(1, other),
      ...fieldBytes(1, cloudflare),
    ]);

    expect(
      GeoIpCidrExtractor.extractCloudflareCidrs(asset),
      ['2001:db8::/32', '203.0.113.0/24'],
    );
  });

  test('fails closed when the Cloudflare tag is absent or empty', () {
    final noTag = Uint8List.fromList([
      ...fieldBytes(1, geoIp('private', [cidr([10, 0, 0, 0], 8)])),
    ]);
    final emptyTag = Uint8List.fromList([
      ...fieldBytes(1, geoIp('cloudflare', [])),
    ]);

    expect(
      () => GeoIpCidrExtractor.extractCloudflareCidrs(noTag),
      throwsFormatException,
    );
    expect(
      () => GeoIpCidrExtractor.extractCloudflareCidrs(emptyTag),
      throwsFormatException,
    );
  });

  test('rejects malformed CIDR prefixes', () {
    final asset = Uint8List.fromList([
      ...fieldBytes(1, geoIp('cloudflare', [cidr([192, 0, 2, 1], 33)])),
    ]);
    expect(
      () => GeoIpCidrExtractor.extractCloudflareCidrs(asset),
      throwsFormatException,
    );
  });
}
