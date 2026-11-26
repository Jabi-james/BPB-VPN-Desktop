import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';
import 'flag_text.dart';

/// Chip showing the selected value; tapping opens a menu with the selected item highlighted.
class ChipMenu<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;

  /// Optional tags after the label (e.g. the protocol), each in its own badge.
  final List<String> Function(T)? badges;

  /// Optional tags under the label, in the open menu only (e.g. a chain proxy's protocol).
  final List<String> Function(T)? subtitleBadges;
  final ValueChanged<T> onSelected;
  final bool enabled;

  const ChipMenu({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    this.badges,
    this.subtitleBadges,
    required this.onSelected,
    this.enabled = true,
  });

  /// Icon and accent for each option in the expanded dropdown.
  /// The collapsed selector remains text-only to keep every selector compact.
  static (IconData, Color) _optionStyle(String value) {
    final text = value.toLowerCase();
    if (text.trim() == 'fastest') return (Icons.fast_forward_rounded, const Color(0xFFFFA34D));
    if (text.contains('masque')) return (Icons.shield_rounded, const Color(0xFF8B7CF6));
    if (text.contains('warp') || text.contains('wireguard')) return (Icons.bolt_rounded, const Color(0xFF25A9E0));
    if (text.contains('vless') || text.contains('worker')) return (Icons.cloud_rounded, const Color(0xFF4F9BFF));
    if (text.contains('psiphon')) return (Icons.public_rounded, const Color(0xFF31B77A));
    if (text.contains('tor') || text.contains('onion')) return (Icons.security_rounded, const Color(0xFF9B7CFF));
    if (text.contains('ssh')) return (Icons.terminal_rounded, const Color(0xFF25BFA5));
    if (text.contains('chain')) return (Icons.link_rounded, const Color(0xFF36B7D8));
    if (text.contains('default') || text.contains('direct')) return (Icons.route_rounded, const Color(0xFF62B878));
    if (text.contains('fastest') || text.contains('region')) return (Icons.location_on_rounded, const Color(0xFFFFA34D));
    if (text.contains('fragment')) return (Icons.tune_rounded, const Color(0xFFB084F5));
    if (text.contains('normal')) return (Icons.check_circle_rounded, const Color(0xFF62B878));
    if (text.contains('packet') || text.contains('fronting')) return (Icons.network_check_rounded, const Color(0xFF26BFA5));
    if (text.contains('dns')) return (Icons.dns_rounded, const Color(0xFF36B7D8));
    return (Icons.settings_rounded, const Color(0xFF8A96A8));
  }

  /// Region labels beginning with a flag emoji use the flag as their visual marker.
  static bool _isCountryFlagLabel(String value) {
    final runes = value.runes;
    if (runes.isEmpty) return false;
    final first = runes.first;
    return first >= 0x1F1E6 && first <= 0x1F1FF;
  }

  /// One tag (a protocol, TCP / UDP…), as the chips show it; also used by ChoicePref.
  static Widget badge(BuildContext context, String text) {
    final theme = Theme.of(context);
    // Keep the VLESS protocol tag recognizable regardless of the user's theme color.
    final isVless = text.toUpperCase() == 'VLESS';
    final background = isVless
        ? const Color(0xFF2563EB)
        : theme.colorScheme.primaryContainer;
    final foreground = isVless
        ? Colors.white
        : theme.colorScheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A few Android builds report a smaller (or zero) bottom view padding for
    // the menu overlay than the navigation bar actually occupies.
    final bottomSystemInset = math.max(
      MediaQuery.viewPaddingOf(context).bottom,
      48.0,
    ).toDouble();
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      // The app-level SafeArea consumes the body padding, but menu overlays can
      // still span to the window edge. Reserve the nav bar inset, with a 48 dp
      // floor for Android builds that under-report it.
      reservedPadding: EdgeInsets.fromLTRB(8, 8, 8, bottomSystemInset + 8),
      style: MenuStyle(shape: WidgetStatePropertyAll(roundedShape(kMenuRadius))),
      menuChildren: [
        for (final v in values)
          MenuItemButton(
            // The selected item gets a tinted background and bold text.
            style: ButtonStyle(
              mouseCursor: WidgetStateMouseCursor.clickable,
              backgroundColor: v == selected
                  ? WidgetStatePropertyAll(scheme.secondaryContainer)
                  : null,
              foregroundColor: v == selected
                  ? WidgetStatePropertyAll(scheme.onSecondaryContainer)
                  : null,
              textStyle: v == selected
                  ? WidgetStatePropertyAll(
                      theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            onPressed: () => onSelected(v),
            // Same width on every row; the name takes the free space, so tags line up on the right.
            child: SizedBox(
              width: 170,
              child: Row(
                children: [
                  if (!_isCountryFlagLabel(label(v))) ...[
                    Builder(builder: (context) {
                      final (icon, color) = _optionStyle(label(v));
                      return Icon(icon, size: 19, color: color);
                    }),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: switch (subtitleBadges?.call(v)) {
                      final tags? when tags.isNotEmpty => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FlagText(label(v), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Wrap(spacing: 4, runSpacing: 4, children: [for (final tag in tags) badge(context, tag)]),
                          ],
                        ),
                      ),
                      _ => FlagText(label(v), maxLines: 1, overflow: TextOverflow.ellipsis),
                    },
                  ),
                  if (badges?.call(v) case final tags?)
                    for (final (i, tag) in tags.indexed) ...[SizedBox(width: i == 0 ? 12 : 4), badge(context, tag)],
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => Material(
        color: scheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          customBorder: const StadiumBorder(),
          onTap: enabled ? () => controller.isOpen ? controller.close() : controller.open() : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: SizedBox(
              width: 170,
              child: Row(
                children: [
                  Expanded(
                    child: FlagText(
                      label(selected),
                      style: theme.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AnimatedRotation(
                    turns: controller.isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Symbols.expand_more_rounded, size: 20, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
