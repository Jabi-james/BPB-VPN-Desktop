import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Decodes the first QR code in a captured desktop image. Returns null when no QR is found.
String? decodeDesktopQr(Uint8List imageBytes) {
  try {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    final rgba = image.convert(numChannels: 4);
    final source = RGBLuminanceSource(
      rgba.width,
      rgba.height,
      rgba.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
    );
    final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    // Invalid image data and images without a QR code are normal scan outcomes.
    return null;
  }
}
