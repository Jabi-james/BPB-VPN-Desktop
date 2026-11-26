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
const _red = Color(0xFFFF4D5A);
const _connecting = Color(0xFF8293A8);
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
      VpnStatus.disconnecting => ('DISCONNECTING', 'Stopping connection…'),
      VpnStatus.disconnected => ('DISCONNECTED', 'Tap to connect'),
    };
    final titleColor = state.isConnected
        ? _green
        : state.status == VpnStatus.disconnected
            ? scheme.onSurface
            : scheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: roundedShape(kHeroRadius, side: BorderSide.none),
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
            const SizedBox(height: 18),
            _Metrics(),
          ],
        ),
      ),
    );
  }
}

/// Connection metrics with compact download/upload cards aligned to My IP and Duration.
class _Metrics extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final since = state.connectedAt;
    final ips = state.myIps;
    final twoIps = state.mode.needsWorker && state.exitNode == ExitNode.worker;
    Widget ip(IpInfo? info, {bool cloudflare = false}) {
      if (!state.isConnected) {
        return const Text('—', textAlign: TextAlign.center);
      }
      if (ips == null) {
        return Text(state.loadingIps ? '…' : '—', textAlign: TextAlign.center);
      }
      if (info == null && !cloudflare) {
        return const Text('Unavailable', textAlign: TextAlign.center);
      }

      final ipText = info?.ip ?? '—';
      final flag = info?.country;
      const yellow = Color(0xFFFFD54F);
      return SizedBox(
        height: 24,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Keep the IP itself on the exact horizontal center of the metric.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Center(
                  child: Text(
                    ipText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            if (cloudflare)
              Positioned(
                left: 0,
                child: Text(
                  'CF',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: yellow,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (flag != null)
              Positioned(
                right: 0,
                child: CountryFlagImage(
                  countryCode: flag,
                  height: 16,
                  width: 24,
                ),
              ),
          ],
        ),
      );
    }

    final refreshIps = state.isConnected ? state.refreshMyIps : null;
    final myIpValue = twoIps
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            ip(ips?.other),
            if (state.isConnected) ...[
              const SizedBox(height: 2),
              ip(ips?.cloudflare, cloudflare: true),
            ],
          ])
        : ip(ips?.other ?? ips?.cloudflare);
    return Column(
      children: [
        Row(textDirection: TextDirection.ltr, children: [
          Expanded(child: _Metric(icon: Symbols.location_on_rounded, label: 'My IP', value: myIpValue, onTap: refreshIps)),
          const SizedBox(width: 8),
          Expanded(child: _Metric(icon: Symbols.speed_rounded, label: 'Ping', value: const _PingButton(), valueWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(child: _Metric(icon: Symbols.timer_rounded, label: 'Duration',
            value: Text(state.isConnected && since != null
              ? formatDuration(DateTime.now().difference(since)) : '—', textAlign: TextAlign.center))),
        ]),
        const SizedBox(height: 8),
        Row(textDirection: TextDirection.ltr, children: [
          Expanded(child: _SpeedMetric(icon: Symbols.download_rounded, value: state.downSpeed, color: const Color(0xFF39FF75))),
          const SizedBox(width: 8),
          const Expanded(child: SizedBox.shrink()),
          const SizedBox(width: 8),
          Expanded(child: _SpeedMetric(icon: Symbols.upload_rounded, value: state.upSpeed, color: const Color(0xFF8B7CFF))),
        ]),
      ],
    );
  }
}

class _SpeedMetric extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  const _SpeedMetric({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.48),
          width: 0.7,
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${formatBytes(value)}/s',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;

  /// Tap action to refresh the displayed exit IP.
  final VoidCallback? onTap;
  final FontWeight valueWeight;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.valueWeight = FontWeight.w400,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.48),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
                weight: 500,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          DefaultTextStyle.merge(
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: valueWeight)
                .merge(_tabular),
            child: SizedBox(
              height: 38,
              child: Align(
                alignment: Alignment.center,
                child: Center(child: value),
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Tooltip(
      message: 'Refresh IP address',
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: content,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
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
    final busy = state.isBusy;
    final fill = switch (state.status) {
      VpnStatus.connected => _green,
      VpnStatus.disconnected => _red,
      _ => _connecting,
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
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _PowerHalo(
            size: widget.size,
            color: state.status == VpnStatus.connected
                ? _green
                : state.status == VpnStatus.disconnected ? _red : _connecting,
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
                      child: busy
                          ? _SpinningArtwork(
                              asset: 'images/icon/Connecting.png',
                              size: widget.size,
                            )
                          : Image.asset(
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


class _PowerHalo extends StatefulWidget {
  final double size;
  final Color color;

  const _PowerHalo({required this.size, required this.color});

  @override
  State<_PowerHalo> createState() => _PowerHaloState();
}

class _PowerHaloState extends State<_PowerHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size + 16,
    height: widget.size + 16,
    child: OverflowBox(
      alignment: Alignment.center,
      minWidth: widget.size + 16,
      minHeight: widget.size + 16,
      maxWidth: widget.size * 1.4,
      maxHeight: widget.size * 1.4,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_pulse.value);
          return Container(
            width: widget.size * (0.96 + 0.42 * t),
            height: widget.size * (0.96 + 0.42 * t),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withValues(alpha: 0.36 + 0.42 * (1 - t)),
                width: 6,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.24 + 0.36 * (1 - t)),
                  blurRadius: 36 + 54 * t,
                  spreadRadius: 3 + 9 * t,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _SpinningArtwork extends StatefulWidget {
  final String asset;
  final double size;

  const _SpinningArtwork({required this.asset, required this.size});

  @override
  State<_SpinningArtwork> createState() => _SpinningArtworkState();
}

class _SpinningArtworkState extends State<_SpinningArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _rotation,
    child: Image.asset(
      widget.asset,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
    ),
  );
}

