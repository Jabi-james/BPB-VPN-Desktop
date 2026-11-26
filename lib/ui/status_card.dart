import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
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
    final compact = defaultTargetPlatform == TargetPlatform.windows;
    final buttonSize = compact ? 104.0 : 116.0;
    final (title, subtitle) = switch (state.status) {
      VpnStatus.connected => ('CONNECTED', 'Tap to disconnect'),
      VpnStatus.connecting => ('CONNECTING', 'Establishing secure connection…'),
      VpnStatus.disconnecting => ('CONNECTING', 'Stopping connection…'),
      VpnStatus.disconnected => ('DISCONNECTED', 'Tap to connect'),
    };
    final titleColor = state.isConnected
        ? _green
        : state.status == VpnStatus.disconnected
            ? scheme.onSurface
            : scheme.primary;

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
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 24,
          vertical: compact ? 16 : 24,
        ),
        child: Column(
          children: [
            const SizedBox(height: 4),
            _PowerButton(size: buttonSize),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SegmentedButton<AppMode>(
                segments: [
                  ButtonSegment<AppMode>(
                    value: AppMode.proxy,
                    label: const Text('Proxy'),
                    icon: const Icon(Symbols.swap_horiz_rounded),
                  ),
                  if (defaultTargetPlatform == TargetPlatform.windows)
                    const ButtonSegment<AppMode>(
                      value: AppMode.systemProxy,
                      label: Text('System Proxy'),
                      icon: Icon(Symbols.desktop_windows_rounded),
                    )
                  else
                    const ButtonSegment<AppMode>(
                      value: AppMode.vpn,
                      label: Text('VPN mode'),
                      icon: Icon(Symbols.shield_rounded),
                    ),
                  if (defaultTargetPlatform == TargetPlatform.windows)
                    const ButtonSegment<AppMode>(
                      value: AppMode.vpn,
                      label: Text('TUN'),
                      icon: Icon(Symbols.language_rounded),
                    ),
                ],
                selected: {state.device.appMode},
                onSelectionChanged: state.isBusy
                    ? null
                    : (selection) => state.setAppMode(selection.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  shape: WidgetStateProperty.all(
                    const StadiumBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _Metrics(),
          ],
        ),
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
    return Row(
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
        Expanded(
          child: _Metric(
            icon: Symbols.location_on_rounded,
            label: 'My IP',
            value: ip(ips?.other ?? (twoIps ? null : ips?.cloudflare)),
            onTap: refreshIps,
          ),
        ),
        if (twoIps)
          Expanded(
            child: _Metric(
              icon: Symbols.cloud_rounded,
              label: 'Cloudflare IP',
              value: ip(ips?.cloudflare),
              onTap: refreshIps,
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;

  /// Tap action to refresh the displayed exit IP.
  final VoidCallback? onTap;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
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
      message: 'Refresh IP address',
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
    final theme = Theme.of(context);
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
