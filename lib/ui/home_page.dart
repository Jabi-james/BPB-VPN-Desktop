import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:material_symbols_icons/symbols.dart';

import 'hover_animated_icon.dart';

import '../state/app_state.dart';
import 'config_view_page.dart';
import 'connection_card.dart';
import 'log_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'status_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final gap = defaultTargetPlatform == TargetPlatform.windows ? 6.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The BPB mark uses both neon blues from the Windows app icon.
            const CustomPaint(
              size: Size(24, 24),
              painter: _BpbMarkPainter(),
            ),
            const SizedBox(width: 6),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'BPB VPN', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' (NotDev)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Logs',
            icon: const HoverAnimatedIcon(child: Icon(Symbols.bug_report_rounded, color: Color(0xFFEF5350), size: 22)),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const LogPage())),
          ),
          IconButton(
            tooltip: 'View config',
            icon: const HoverAnimatedIcon(child: Icon(Symbols.data_object_rounded, color: Color(0xFF26A69A), size: 22)),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ConfigViewPage())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const HoverAnimatedIcon(child: Icon(Symbols.settings_rounded, color: Color(0xFF4C8BF5), size: 22)),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Image.asset(
                    'images/icon/bg.jpg',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.18),
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
              if (state.needsReconnect) const _ReconnectBanner(),
              SizedBox(height: gap),
              const ConnectionCard(),
              SizedBox(height: defaultTargetPlatform == TargetPlatform.windows ? 8 : 16),
              const StatusCard(),
              SizedBox(height: defaultTargetPlatform == TargetPlatform.windows ? 8 : 16),
            ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      shape: roundedShape(
        kCardRadius,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
          width: 0.75,
        ),
      ),
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 0,
      child: ListTile(
        leading: Icon(
          Symbols.sync_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Settings changed'),
        subtitle: const Text('Reconnect to apply them.'),
        trailing: FilledButton.tonal(
          onPressed: state.reconnect,
          child: const Text('Apply'),
        ),
      ),
    );
  }
}

/// Small, crisp two-blue BPB mark for the app bar. The shell/taskbar icon is
/// generated separately from bpb_icon.svg and is intentionally unaffected.
class _BpbMarkPainter extends CustomPainter {
  const _BpbMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void circle(Offset center, double radius, List<Color> colors) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.25,
          colors: colors,
        ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
    }

    circle(
      Offset(size.width * 0.36, size.height * 0.65),
      size.width * 0.34,
      const [Color(0xFF42B7FF), Color(0xFF0874E8), Color(0xFF0752B5)],
    );
    circle(
      Offset(size.width * 0.66, size.height * 0.27),
      size.width * 0.17,
      const [Color(0xFF8ADFFF), Color(0xFF36AFFF), Color(0xFF168BFF)],
    );
    circle(
      Offset(size.width * 0.79, size.height * 0.57),
      size.width * 0.115,
      const [Color(0xFF62C8FF), Color(0xFF168BFF), Color(0xFF0752B5)],
    );
  }

  @override
  bool shouldRepaint(covariant _BpbMarkPainter oldDelegate) => false;
}
