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
import 'format.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _connectionCardKey = GlobalKey<ConnectionCardState>();

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
          if (state.isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _SpeedIndicator(icon: Symbols.download_rounded, value: state.downSpeed, color: const Color(0xFF39FF75)),
                const SizedBox(width: 7),
                _SpeedIndicator(icon: Symbols.upload_rounded, value: state.upSpeed, color: const Color(0xFF8B7CFF)),
              ]),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.needsReconnect)
                    _ReconnectBanner(onApply: () async {
                      _connectionCardKey.currentState?.collapse();
                      await state.reconnect();
                    }),
                  SizedBox(height: gap),
                  ConnectionCard(key: _connectionCardKey),
                  SizedBox(height: defaultTargetPlatform == TargetPlatform.windows ? 10 : 16),
                  const StatusCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedIndicator extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  const _SpeedIndicator({required this.icon, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 82, maxWidth: 94),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Flexible(child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('${formatBytes(value)}/s',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        )),
      ]),
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  final Future<void> Function() onApply;
  const _ReconnectBanner({required this.onApply});

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
          onPressed: onApply,
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
