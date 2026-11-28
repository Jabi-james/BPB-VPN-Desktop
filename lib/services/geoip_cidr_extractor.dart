import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Extracts CIDR entries from Xray's GeoIPList protobuf asset.
class GeoIpCidrExtractor {
  const GeoIpCidrExtractor._();

  /// Returns normalized, unique CIDRs from the [cloudflare] GeoIP tag.
  static List<String> extractCloudflareCidrs(Uint8List data) {
    final result = <String>{};
    final list = _ProtoReader(data);
    while (!list.isDone) {
      final key = list.readVarint();
      final field = key >> 3;
      final wire = key & 7;
      if (field == 1 && wire == 2) {
        final geoIp = _readBytes(list);
        _readGeoIp(geoIp, result);
      } else {
        list.skip(wire);
      }
    }
    if (result.isEmpty) {
      throw const FormatException(
        'geoip.dat does not contain a non-empty geoip:cloudflare entry.',
      );
    }
    final cidrs = result.toList()..sort();
    return cidrs;
  }

  static void _readGeoIp(Uint8List data, Set<String> output) {
    final reader = _ProtoReader(data);
    String? tag;
    final entries = <Uint8List>[];
    while (!reader.isDone) {
      final key = reader.readVarint();
      final field = key >> 3;
      final wire = key & 7;
      if (wire == 2 && field == 1) {
        tag = utf8.decode(_readBytes(reader), allowMalformed: false);
      } else if (wire == 2 && field == 2) {
        entries.add(_readBytes(reader));
      } else {
        reader.skip(wire);
      }
    }
    if (tag?.toLowerCase() != 'cloudflare') return;
    for (final entry in entries) {
      output.add(_readCidr(entry));
    }
  }

  static String _readCidr(Uint8List data) {
    final reader = _ProtoReader(data);
    Uint8List? address;
    int? prefix;
    while (!reader.isDone) {
      final key = reader.readVarint();
      final field = key >> 3;
      final wire = key & 7;
      if (wire == 2 && field == 1) {
        address = _readBytes(reader);
      } else if (wire == 0 && field == 2) {
        prefix = reader.readVarint();
      } else {
        reader.skip(wire);
      }
    }
    if (address == null || prefix == null ||
        (address.length != 4 && address.length != 16)) {
      throw const FormatException('Invalid CIDR entry in geoip:cloudflare.');
    }
    final bits = address.length * 8;
    if (prefix < 0 || prefix > bits) {
      throw FormatException('Invalid CIDR prefix length: $prefix.');
    }
    final network = Uint8List.fromList(address);
    var remaining = prefix;
    for (var i = 0; i < network.length; i++) {
      if (remaining >= 8) {
        remaining -= 8;
      } else if (remaining <= 0) {
        network[i] = 0;
      } else {
        network[i] &= (0xff << (8 - remaining)) & 0xff;
        remaining = 0;
      }
    }
    return '${InternetAddress.fromRawAddress(network).address}/$prefix';
  }

  static Uint8List _readBytes(_ProtoReader reader) {
    final length = reader.readVarint();
    return reader.readSlice(length);
  }
}

class _ProtoReader {
  final Uint8List bytes;
  int offset = 0;

  _ProtoReader(this.bytes);

  bool get isDone => offset == bytes.length;

  int readVarint() {
    var value = 0;
    var shift = 0;
    while (offset < bytes.length && shift < 64) {
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return value;
      shift += 7;
    }
    throw const FormatException('Malformed protobuf varint.');
  }

  Uint8List readSlice(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('Truncated protobuf field.');
    }
    final result = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return result;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        readVarint();
        break;
      case 1:
        readSlice(8);
        break;
      case 2:
        readSlice(readVarint());
        break;
      case 5:
        readSlice(4);
        break;
      default:
        throw FormatException('Unsupported protobuf wire type: $wire.');
    }
  }
}
