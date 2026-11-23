import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

/// Renders country regional-indicator pairs as actual flag images instead of platform emoji.
class FlagText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  const FlagText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    final runes = text.runes.toList(growable: false);
    final spans = <InlineSpan>[];
    final plain = StringBuffer();

    void flush() {
      if (plain.isEmpty) return;
      spans.add(TextSpan(text: plain.toString()));
      plain.clear();
    }

    for (var i = 0; i < runes.length; i++) {
      final first = runes[i];
      if (first >= 0x1F1E6 && first <= 0x1F1FF &&
          i + 1 < runes.length &&
          runes[i + 1] >= 0x1F1E6 && runes[i + 1] <= 0x1F1FF) {
        flush();
        final country = String.fromCharCodes([
          first - 0x1F1E6 + 0x41,
          runes[++i] - 0x1F1E6 + 0x41,
        ]);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CountryFlag.fromCountryCode(
              country,
              theme: const ImageTheme(width: 18, height: 12),
            ),
          ),
        ));
      } else {
        plain.writeCharCode(first);
      }
    }
    flush();

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: maxLines == null,
    );
  }
}

/// Small rectangular image flag for IP rows.
class CountryFlagImage extends StatelessWidget {
  final String countryCode;
  final double height;
  final double width;

  const CountryFlagImage({
    super.key,
    required this.countryCode,
    this.height = 14,
    this.width = 21,
  });

  @override
  Widget build(BuildContext context) => CountryFlag.fromCountryCode(
    countryCode,
    theme: ImageTheme(width: width, height: height),
  );
}
