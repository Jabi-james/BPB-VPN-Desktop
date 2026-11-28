import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Decodes a QR code from a captured desktop image.
///
/// This mirrors v2rayN's decode sequence: decode the captured bitmap once,
/// then retry after a horizontal flip when the first pass finds nothing.
String? decodeDesktopQr(Uint8List imageBytes) {
  try {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    final result = _decodeBitmap(image);
    if (result != null && result.isNotEmpty) return result;

    final mirrored = img.copyFlip(
      image,
      direction: img.FlipDirection.horizontal,
    );
    final mirroredResult = _decodeBitmap(mirrored);
    if (mirroredResult != null && mirroredResult.isNotEmpty) {
      return mirroredResult;
    }
  } catch (_) {
    // Invalid image data and images without a QR code are normal scan outcomes.
  }
  return null;
}

String? _decodeBitmap(img.Image image) {
  final rgba = image.convert(numChannels: 4);
  final source = RGBLuminanceSource(
    rgba.width,
    rgba.height,
    rgba.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
  );
  final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
  return QRCodeReader().decode(bitmap).text;
}
