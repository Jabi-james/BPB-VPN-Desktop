import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:material_symbols_icons/symbols.dart';

import 'hover_animated_icon.dart';

import '../models/settings.dart';
import '../state/app_state.dart';
import 'chip_menu.dart';
import 'config_view_page.dart';
import 'connection_card.dart';
import 'format.dart';
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
            const Text('BPB VPN', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          // VPN captures all traffic; System Proxy changes Windows' proxy setting; Proxy exposes only the local port.
          ChipMenu(
            values: defaultTargetPlatform == TargetPlatform.windows
              ? AppMode.values
              : const [AppMode.vpn, AppMode.proxy],
            selected: state.device.appMode,
            label: (v) => switch (v) {
              AppMode.vpn => defaultTargetPlatform == TargetPlatform.windows ? 'TUN mode' : 'VPN mode',
              AppMode.systemProxy => 'System Proxy',
              AppMode.proxy => 'Proxy mode',
            },
            onSelected: state.setAppMode,
            enabled: !state.isBusy,
          ),
          const SizedBox(width: 4),
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
              const _TrafficRow(),
              SizedBox(height: defaultTargetPlatform == TargetPlatform.windows ? 8 : 16),
              // Worker requests only matter for the types that use the worker (Worker).
              if (state.worker != null && state.mode.needsWorker)
                const _UsageCard(),
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

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Compact Download and Upload cards; session totals are intentionally hidden.
/// Always laid out so the connect button doesn't jump when the VPN connects.
class _TrafficRow extends StatelessWidget {
  const _TrafficRow();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _TrafficCard(
                  icon: Symbols.arrow_downward_rounded,
                  label: 'Download',
                  accent: const Color(0xFF39FF75),
                  rate: state.downSpeed,
                  total: state.allTimeDown,
                  ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _TrafficCard(
                  icon: Symbols.arrow_upward_rounded,
                  label: 'Upload',
                  accent: const Color(0xFFFF5555),
                  rate: state.upSpeed,
                  total: state.allTimeUp,
                  ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final int rate;
  final int total;

  const _TrafficCard({
    required this.icon,
    required this.label,
    required this.accent,
    required this.rate,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: roundedShape(
        kCardRadius,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
          width: 0.75,
        ),
      ),
      color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.80),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: defaultTargetPlatform == TargetPlatform.windows ? 8 : 16,
          horizontal: defaultTargetPlatform == TargetPlatform.windows ? 14 : 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: defaultTargetPlatform == TargetPlatform.windows ? 4 : 6,
          children: [
            Row(
              spacing: 6,
              children: [
                Icon(icon, size: 18, weight: 700, color: accent),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: accent, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Text(
              '${formatBytes(rate)}/s',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)
                  .merge(_tabular),
            ),
            Text(
              'Total  ${formatBytes(total)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card with a title, a refresh button and a body, used by My IP and Usage.
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool loading;
  final VoidCallback onRefresh;
  final List<Widget> children;
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.loading,
    required this.onRefresh,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      shape: roundedShape(
        kCardRadius,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
          width: 0.75,
        ),
      ),
      color: theme.colorScheme.surfaceContainer,
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: defaultTargetPlatform == TargetPlatform.windows ? 8 : 20,
          horizontal: defaultTargetPlatform == TargetPlatform.windows ? 16 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Refresh',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.refresh_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
            // Padding(
            //   padding: const EdgeInsets.only(right: 0),
            // ),
          ],
        ),
      ),
    );
  }
}

/// Label on the left, [value] right-aligned.
class _KeyValue extends StatelessWidget {
  final String label;
  final Widget value;
  const _KeyValue(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: value),
        ),
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard();

  /// Workers free plan daily request limit (shared by the whole account).
  static const _limit = 100000;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final usage = state.usage;
    final style = theme.textTheme.bodyMedium?.merge(_tabular);
    return _InfoCard(
      icon: Symbols.data_usage_rounded,
      title: 'Requests · last 24h',
      loading: state.loadingUsage,
      onRefresh: state.refreshUsage,
      children: [
        if (usage != null) ...[
          _KeyValue(
            'This worker',
            Text(
              formatCount(usage.worker),
              style: style?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          _AccountUsage(total: usage.total, limit: _limit),
        ] else if (state.usageError == null)
          Text(
            state.loadingUsage ? 'Loading…' : '—',
            style: theme.textTheme.bodyMedium,
          ),
        if (state.usageError != null)
          Padding(
            padding: EdgeInsets.only(top: usage != null ? 8 : 0),
            child: Text(
              state.usageError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// "12,345 · 12.3%" with a bar against the daily limit.
class _AccountUsage extends StatelessWidget {
  final int total;
  final int limit;
  const _AccountUsage({required this.total, required this.limit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total / limit;
    final style = theme.textTheme.bodyMedium?.merge(_tabular);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValue(
          'Account total',
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${(ratio * 100).toStringAsFixed(1)}% · '),
                TextSpan(
                  text: formatCount(total),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            style: style,
          ),
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          color: ratio >= 0.9 ? theme.colorScheme.error : null,
        ),
      ],
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
