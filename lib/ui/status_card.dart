import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../services/my_ip.dart';
import '../services/vpn_channel.dart';
import '../state/app_state.dart';
import 'format.dart';
import 'theme.dart';
import 'flag_text.dart';

/// Connected colour; stays green whatever theme colour is picked.
const _green = Color(0xFF39FF75);
const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

// Layout constants: the power button is positioned from these.
const _pad = 24.0;
const _rowHeight = 124.0;
const _button = 116.0;

/// Home status card: state, power button, duration, ping and exit IPs (the connection's
/// settings are on the ConnectionCard above it).
class StatusCard extends StatefulWidget {
  const StatusCard({super.key});

  @override
  State<StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<StatusCard> {
  /// Ticks the connection duration.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppScope.read(context).isConnected) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed =
        state.status == VpnStatus.disconnected && state.error != null;
    final (title, subtitle) = switch (state.status) {
      // Psiphon / Tor say what they're doing: progress while connecting, or reconnecting.
      VpnStatus.connected => (
        'CONNECTED',
        state.exitDetail ?? 'Tap to disconnect',
      ),
      VpnStatus.connecting => (
        state.connectedAt == null ? 'CONNECTING' : 'RECONNECTING',
        state.exitDetail ??
            (state.tunMode ? 'Starting the tunnel…' : 'Checking connection…'),
      ),
      VpnStatus.disconnecting => ('DISCONNECTING', 'Stopping the tunnel…'),
      VpnStatus.disconnected when failed => ('Connection failed', state.error!),
      VpnStatus.disconnected => ('DISCONNECTED', 'Tap to connect'),
    };
    final titleColor = state.isConnected
        ? _green
        : (failed ? scheme.error : scheme.onSurface);
    final muted = scheme.onSurfaceVariant;
    final compact = defaultTargetPlatform == TargetPlatform.windows;
    final pad = compact ? 12.0 : _pad;
    final rowHeight = compact ? 72.0 : _rowHeight;
    final buttonSize = compact ? 88.0 : _button;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: scheme.surfaceContainer.withValues(alpha: 0.80),
      elevation: 0,
      shape: roundedShape(
        kHeroRadius,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
          width: 0.75,
        ),
      ),
      child: Stack(
        // Let the button's shadow spill past the card edge instead of being cut off.
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and hint on the left; space for the button on the right.
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: rowHeight),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: titleColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 16 + buttonSize),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 8 : 16),
                _Metrics(),
              ],
            ),
          ),
          Positioned(
            right: pad - 8,
            top: pad - 8,
            width: buttonSize + 16,
            height: buttonSize + 16,
            child: _PowerButton(size: buttonSize),
          ),
        ],
      ),
    );
  }
}

/// Duration, ping and the two exit IPs in a 2×2 grid.
class _Metrics extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final since = state.connectedAt;
    final ips = state.myIps;

    Widget ip(IpInfo? info) {
      if (!state.isConnected) return const Text('—');
      if (ips == null) return Text(state.loadingIps ? '…' : '—');
      if (info == null) return const Text('Unavailable');
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(info.ip, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (info.country != null) ...[
            const SizedBox(width: 6),
            CountryFlagImage(countryCode: info.country!),
          ],
        ],
      );
    }

    final refreshIps = state.isConnected ? state.refreshMyIps : null;
    final twoIps = state.mode.needsWorker && state.exitNode == ExitNode.worker;
    // This phone's LAN address (always shown); with LAN connections allowed, other
    // devices use it with port 10808 for the SOCKS/HTTP proxy.
    final lanIp = state.lanIp;
    final lan = _Metric(
      icon: Symbols.network_node_rounded,
      label: 'LAN IP',
      value: Text(lanIp ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
      tooltip: 'Tap to copy',
      onTap: lanIp == null
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: lanIp));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Copied $lanIp')));
            },
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: Symbols.timer_rounded,
                label: 'Duration',
                value: Text(
                  state.isConnected && since != null
                      ? formatDuration(DateTime.now().difference(since))
                      : '—',
                ),
              ),
            ),
            Expanded(
              child: _Metric(
                icon: Symbols.speed_rounded,
                label: 'Ping',
                value: const _PingButton(),
              ),
            ),
          ],
        ),
        SizedBox(height: defaultTargetPlatform == TargetPlatform.windows ? 8 : 14),
        // Through the worker alone, Cloudflare-hosted sites see the proxy IP and others the
        // worker's exit IP. WARP, Serverless and the chain / Psiphon exits have a single exit IP.
        Row(
          children: twoIps
              ? [
                  Expanded(
                    child: _Metric(
                      icon: Symbols.location_on_rounded,
                      label: 'My IP',
                      value: ip(ips?.other),
                      onTap: refreshIps,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      icon: Symbols.location_on_rounded,
                      label: 'My IP Cloudflare',
                      value: ip(ips?.cloudflare),
                      onTap: refreshIps,
                    ),
                  ),
                ]
              : [
                  Expanded(
                    child: _Metric(
                      icon: Symbols.location_on_rounded,
                      label: 'My IP',
                      value: ip(ips?.other ?? ips?.cloudflare),
                      onTap: refreshIps,
                    ),
                  ),
                  Expanded(child: lan),
                ],
        ),
        // Both target IPs fill the row, so the LAN IP gets its own.
        if (twoIps) ...[const SizedBox(height: 14), lan],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;

  /// Tap action (refresh the IPs, copy the proxy address) and its hint.
  final VoidCallback? onTap;
  final String tooltip;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.tooltip = 'Tap to refresh',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
              weight: 500,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)
              .merge(_tabular),
          child: SizedBox(
            height: 28,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: value,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) {
      return Padding(padding: const EdgeInsets.only(right: 8), child: content);
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
   mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: content,
        ),
      ),
    );
  }
}

/// Tests the tunnel ping and shows an image warning when no ping is available.
class _PingButton extends StatelessWidget {
  const _PingButton();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final ping = state.pingMs;
    if (!state.isConnected) return const Text('—');
    final noPing = ping == null || ping < 0;
    const color = _green;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 8, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.ltr,
        children: [
          if (state.pinging) ...[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Testing',
              textDirection: TextDirection.ltr,
              style: TextStyle(color: color),
            ),
          ] else ...[
            if (noPing) ...[
              Image.asset(
                'images/icon/Warning.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              noPing ? 'Timeout' : '$ping ms',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: noPing ? theme.colorScheme.error : color,
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: 'Test ping',
      child: InkWell(
   mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(16),
        onTap: state.pinging ? null : state.testPing,
        child: content,
      ),
    );
  }
}

/// Big round power button. The icon points down while disconnected and flips up when
/// connecting/connected; it glows when connected and shows a spinning ring while busy.
class _PowerButton extends StatefulWidget {
  final double size;
  const _PowerButton({this.size = _button});

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> {
  bool _pressed = false;

  /// Icon rotation in turns. It only ever grows by half a turn, so the icon always
  /// spins clockwise: down → up on connect, up → down on disconnect.
  double? _turns;
  bool? _up;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final busy = state.isBusy;
    final (Color fill, Color iconColor) = switch (state.status) {
      VpnStatus.connected => (_green, Colors.white),
      VpnStatus.disconnected => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      _ => (scheme.primary, scheme.onPrimary),
    };
    final up =
        state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting;
    if (_up == null) {
      _turns = up ? 0 : 0.5;
    } else if (_up != up) {
      _turns = _turns! + 0.5;
    }
    _up = up;
    const duration = Duration(milliseconds: 500);

    return Semantics(
      button: true,
      label: state.status == VpnStatus.disconnected ? 'Connect' : 'Disconnect',
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (state.status == VpnStatus.connected || state.status == VpnStatus.disconnected)
            TweenAnimationBuilder<double>(
              key: ValueKey(state.status),
              tween: Tween(begin: 0.86, end: 1.18),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOut,
              builder: (context, value, _) => Container(
                width: widget.size * value,
                height: widget.size * value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (state.status == VpnStatus.connected ? _green : Colors.red)
                        .withValues(alpha: (1.18 - value).clamp(0.0, 0.22).toDouble()),
                    width: 3,
                  ),
                ),
              ),
            ),
          if (busy)
            Positioned.fill(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
                color: fill,
              ),
            ),
          AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // A slightly lighter top-left gives the button some depth.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(fill, Colors.white, 0.18)!, fill],
                ),
                boxShadow: [
                  // Coloured glow, stronger when connected.
                  BoxShadow(
                    color: fill.withValues(
                      alpha: state.isConnected ? 0.5 : 0.3,
                    ),
                    blurRadius: state.isConnected ? 32 : 24,
                    offset: const Offset(0, 10),
                  ),
                  // Tight contact shadow under the button.
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
   mouseCursor: WidgetStateMouseCursor.clickable,
                  // Always tappable: while connecting (Psiphon may search for a long time) it cancels.
                  onTap: state.toggle,
                  onHighlightChanged: (v) => setState(() => _pressed = v),
                  child: Center(
                    child: AnimatedRotation(
                      turns: _turns!,
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutBack,
                      child: Image.asset(
                        state.status == VpnStatus.connected
                            ? 'images/icon/Connected.png'
                            : 'images/icon/Disconnected.png',
                        width: widget.size,
                        height: widget.size,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
