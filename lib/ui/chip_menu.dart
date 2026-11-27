import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';
import 'flag_text.dart';

/// Chip showing the selected value; tapping opens a menu with the selected item highlighted.
class ChipMenu<T> extends StatelessWidget {
  final List<T> values;
  final T? selected;
  final String? placeholder;
  final double width;
  final bool expand;
  final String Function(T) label;

  /// Optional tags after the label (e.g. the protocol), each in its own badge.
  final List<String> Function(T)? badges;

  /// Optional tags under the label, in the open menu only (e.g. a chain proxy's protocol).
  final List<String> Function(T)? subtitleBadges;
  final ValueChanged<T> onSelected;
  final bool enabled;

  /// Disables individual menu options without disabling the whole selector.
  final bool Function(T)? isValueEnabled;

  const ChipMenu({
    super.key,
    required this.values,
    required this.selected,
    this.placeholder,
    this.width = 170,
    this.expand = false,
    required this.label,
    this.badges,
    this.subtitleBadges,
    required this.onSelected,
    this.enabled = true,
    this.isValueEnabled,
  });

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
            // Registration-dependent choices remain visible but cannot be selected.
            onPressed: (isValueEnabled?.call(v) ?? true) ? () => onSelected(v) : null,
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
            // Same width on every row; the name takes the free space, so tags line up on the right.
            child: SizedBox(
              width: width,
              child: Row(
                children: [
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
              width: expand ? double.infinity : width,
              child: Row(
                children: [
                  Expanded(
                    child: FlagText(
                      selected == null ? (placeholder ?? '') : label(selected as T),
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
