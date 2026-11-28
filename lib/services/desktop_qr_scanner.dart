import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Decodes a QR code from a captured desktop image.
///
/// Follows v2rayN's sequence: decode the captured bitmap, then retry after a
/// horizontal flip when the first pass does not find a QR code.
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
  try {
    final rgba = image.convert(numChannels: 4);
    final source = RGBLuminanceSource(
      rgba.width,
      rgba.height,
      rgba.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
    );
    // ZXing.Net's default bitmap reader uses hybrid thresholding.
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    // A failed first pass must not prevent v2rayN's mirrored retry.
    return null;
  }
}
