import 'dart:typed_data';

import 'package:bpb/services/desktop_qr_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

Uint8List _qrPng(String value) {
  final matrix = Encoder.encode(value, ErrorCorrectionLevel.h).matrix!;
  const scale = 5;
  final image = img.Image(
    width: matrix.width * scale,
    height: matrix.height * scale,
    numChannels: 4,
  );
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: image.width - 1,
    y2: image.height - 1,
    color: img.ColorRgba8(255, 255, 255, 255),
  );
  for (var x = 0; x < matrix.width; x++) {
    for (var y = 0; y < matrix.height; y++) {
      if (matrix.get(x, y) == 1) {
        img.fillRect(
          image,
          x1: x * scale,
          y1: y * scale,
          x2: (x + 1) * scale - 1,
          y2: (y + 1) * scale - 1,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      }
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('decodes a VLESS share link from a desktop screenshot', () {
    const link = 'vless://11111111-2222-4333-8444-555555555555@example.com:443#Desktop';
    expect(decodeDesktopQr(_qrPng(link)), link);
  });

  test('retries QR decoding after mirroring the desktop screenshot horizontally', () {
    const link = 'vless://11111111-2222-4333-8444-555555555555@example.com:443#Desktop';
    final mirrored = img.decodePng(_qrPng(link))!;
    img.flipHorizontal(mirrored);
    expect(decodeDesktopQr(Uint8List.fromList(img.encodePng(mirrored))), link);
  });

  test('returns null when the screenshot has no valid QR image', () {
    expect(decodeDesktopQr(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
