import 'dart:async';

import 'package:flutter/material.dart';

/// A lightweight, non-modal notification shown at the top of the app.
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    final message = _plainText(snackBar.content);
    if (message.isNotEmpty) show(context, message);
  }

  static String _plainText(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText() ?? '';
    }
    if (widget is Padding && widget.child != null) return _plainText(widget.child!);
    if (widget is Center && widget.child != null) return _plainText(widget.child!);
    if (widget is Align && widget.child != null) return _plainText(widget.child!);
    if (widget is Row) {
      return widget.children.map(_plainText).where((s) => s.isNotEmpty).join(' ');
    }
    if (widget is Column) {
      return widget.children.map(_plainText).where((s) => s.isNotEmpty).join(' ');
    }
    return '';
  }

  static void show(BuildContext context, String message) {
    if (!context.mounted || message.trim().isEmpty) return;
    hide();
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        message: message,
        onDismiss: () {
          if (identical(_entry, entry)) hide();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(seconds: 5), hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ToastOverlay({required this.message, required this.onDismiss});

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: TapRegion(
            consumeOutsideTaps: false,
            onTapOutside: (_) => widget.onDismiss(),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1.25),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOutCubic,
              )),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOut,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .5,
                  ),
                  child: Material(
                    color: const Color(0xFF202329),
                    elevation: 10,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lightbulb_rounded,
                            color: Color(0xFFFFD166),
                            size: 21,
                          ),
                          const SizedBox(width: 11),
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                fontSize: 14.5,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
