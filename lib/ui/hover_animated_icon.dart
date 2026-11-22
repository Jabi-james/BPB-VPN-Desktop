import 'package:flutter/material.dart';

/// Small, consistent hover animation for colorful navigation and toolbar icons.
class HoverAnimatedIcon extends StatefulWidget {
  final Widget child;
  const HoverAnimatedIcon({required this.child, super.key});
  @override
  State<HoverAnimatedIcon> createState() => _HoverAnimatedIconState();
}
class _HoverAnimatedIconState extends State<HoverAnimatedIcon> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedScale(scale: _hovered ? 1.12 : 1,
      duration: const Duration(milliseconds: 170), curve: Curves.easeOut,
      child: AnimatedRotation(turns: _hovered ? 0.035 : 0,
        duration: const Duration(milliseconds: 170), curve: Curves.easeOut,
        child: widget.child)));
}
