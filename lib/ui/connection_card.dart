import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

import '../models/settings.dart';
import '../services/chain_proxy.dart';
import '../services/my_ip.dart';
import '../services/xray_config.dart';
import '../state/app_state.dart';
import 'chip_menu.dart';
import 'theme.dart';

/// The connection's settings, above the status card: its type and mode, and where traffic
/// leaves for the internet (the connection itself, the chain proxy, or Psiphon / Tor in a
/// chosen region).
class ConnectionCard extends StatefulWidget {
  const ConnectionCard({super.key});

  @override
  State<ConnectionCard> createState() => ConnectionCardState();
}

class ConnectionCardState extends State<ConnectionCard> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _panelEntry;

  void collapse() {
    final entry = _panelEntry;
    if (entry == null) return;
    _panelEntry = null;
    entry.remove();
    if (mounted) setState(() {});
  }

  void _togglePanel() {
    if (_panelEntry != null) {
      collapse();
      return;
    }
    _panelEntry = OverlayEntry(builder: (overlayContext) {
      final media = MediaQuery.of(overlayContext);
      final state = AppScope.of(overlayContext);
      final theme = Theme.of(overlayContext);
      final scheme = theme.colorScheme;
      final exit = state.exitNode;
      final isServerlessDns = state.mode == ConnectionMode.serverless &&
          state.serverlessMode == ServerlessMode.dns;
      final hasExitNode = state.mode != ConnectionMode.psiphon &&
          state.mode != ConnectionMode.tor &&
          state.mode != ConnectionMode.aether &&
          !isServerlessDns;
      final nodes = switch (state.mode) {
        ConnectionMode.serverless => state.serverlessMode == ServerlessMode.domainFronting
            ? [ExitNode.worker, ExitNode.psiphon]
            : [ExitNode.worker, ExitNode.psiphon, ExitNode.tor],
        _ => [
            for (final n in ExitNode.values)
              if (n != ExitNode.chain || state.usableChains.isNotEmpty) n,
          ],
      };
      final chain = state.exitChain;
      return Stack(
        children: [
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: const Offset(12, 68),
            child: Material(
              elevation: 18,
              color: Color.lerp(scheme.surfaceContainer, Colors.black, 0.18)!,
              shape: roundedShape(kHeroRadius,
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.9), width: 0.9)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: media.size.width - 24,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    defaultTargetPlatform == TargetPlatform.windows ? 16 : 20,
                    10,
                    defaultTargetPlatform == TargetPlatform.windows ? 16 : 20,
                    12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Row(icon: Symbols.category_rounded, color: const Color(0xFF4F9BFF), label: 'Type',
                        selector: const _TypeSelector()),
                      if (state.showCoreSelector)
                        _Row(icon: Symbols.memory_rounded, color: const Color(0xFF9B7CFF), label: 'Core',
                          selector: ChipMenu(
                            values: CoreType.values, selected: state.core,
                            label: (core) => core.label, onSelected: state.setCore,
                            isValueEnabled: (core) => state.isCoreRegistered(core, state.mode),
                            enabled: !state.isBusy)),
                      if (state.hasModeOption)
                        const _Row(icon: Symbols.tune_rounded, color: Color(0xFF26BFA5), label: 'Mode',
                          selector: _ModeSelector()),
                      if (hasExitNode)
                        _Row(icon: Symbols.exit_to_app_rounded, color: const Color(0xFFFFA34D), label: 'Exit Node',
                          selector: ChipMenu(
                            values: nodes, selected: exit,
                            label: (n) => switch (n) {
                              ExitNode.worker => 'Default',
                              ExitNode.chain => 'Chain proxy',
                              ExitNode.psiphon => 'Psiphon',
                              ExitNode.tor => 'Tor',
                            },
                            badges: (n) => ConnectionCardState._transports(n, state.mode, chain: chain),
                            onSelected: state.setExitNode,
                            enabled: !state.isBusy && nodes.length > 1)),
                      if (!isServerlessDns && (exit == ExitNode.psiphon || exit == ExitNode.tor))
                        _Row(icon: Symbols.location_on_rounded, color: const Color(0xFF62B878), label: 'Region',
                          selector: ChipMenu(
                            values: ['', ...exitRegions.keys],
                            selected: state.device.exitRegion,
                            label: ConnectionCardState._regionLabel,
                            onSelected: state.setExitRegion,
                            enabled: !state.isBusy)),
                      if (exit == ExitNode.chain && chain != null)
                        _Row(icon: Symbols.link_rounded, color: const Color(0xFF36B7D8), label: 'Chain',
                          selector: ChipMenu(
                            values: state.usableChains, selected: chain,
                            label: (c) => c.name,
                            subtitleBadges: (c) => ChainInfo.of(c.link)?.tags ?? const [],
                            onSelected: state.setExitChain,
                            enabled: !state.isBusy && state.usableChains.length > 1)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
    Overlay.of(context, rootOverlay: true).insert(_panelEntry!);
    setState(() {});
  }

  @override
  void dispose() {
    _panelEntry?.remove();
    _panelEntry = null;
    super.dispose();
  }

  static List<String> _transports(
    ExitNode node,
    ConnectionMode mode, {
    required ChainProxy? chain,
  }) => switch (node) {
    ExitNode.worker => switch (mode) {
      ConnectionMode.worker || ConnectionMode.ssh => const ['TCP'],
      ConnectionMode.warp || ConnectionMode.masque => const ['TCP', 'UDP'],
      _ => const [],
    },
    ExitNode.chain => chain == null ? const [] : ChainInfo.of(chain.link)?.carries ?? const [],
    ExitNode.psiphon => mode == ConnectionMode.ssh ? const ['TCP'] : const ['TCP', 'UDP'],
    ExitNode.tor => const ['TCP'],
  };

  static String _regionLabel(String code) => code.isEmpty
      ? 'Fastest'
      : '${countryFlag(code)} ${exitRegions[code] ?? code}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CompositedTransformTarget(
      link: _link,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        shape: roundedShape(kHeroRadius,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.75), width: 0.75)),
        color: scheme.surfaceContainer.withValues(alpha: 0.72),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: _togglePanel,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                  child: Icon(Symbols.wifi_tethering_rounded, color: scheme.primary, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Connections',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Configure How to Connect and Routing Options',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                )),
                const SizedBox(width: 8),
                Icon(_panelEntry == null ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                  color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget selector;
  final Color color;
  const _Row({required this.icon, required this.label, required this.selector, this.color = Colors.white});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: defaultTargetPlatform == TargetPlatform.windows ? 42 : 48,
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        const SizedBox(width: 8),
        selector,
      ]),
    );
  }
}

/// Connection types. Every type except Serverless connects with a best-ping config.
class _TypeSelector extends StatelessWidget {
  const _TypeSelector();

  static String _protocol(ConnectionMode m) => switch (m) {
    ConnectionMode.worker => 'HTTPS',
    ConnectionMode.warp => 'WireGuard',
    // CONNECT-IP over HTTP/2 or 3: HTTPS either way.
    ConnectionMode.masque => 'HTTPS',
    ConnectionMode.aether => 'MASQUE',
    ConnectionMode.serverless => 'Direct',
    ConnectionMode.ssh => 'SSH',
    // Psiphon's tunnels are all SSH based, under various obfuscation layers.
    ConnectionMode.psiphon => 'SSH',
    ConnectionMode.tor => 'Onion',
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ChipMenu(
      // Only what's installed (see AppState.availableModes).
      values: state.availableModes,
      selected: state.mode,
      label: (m) => m == ConnectionMode.worker ? 'VLESS' : m.label,
      badges: (m) => [_protocol(m)],
      onSelected: state.setMode,
      isValueEnabled: state.isModeSelectable,
      enabled: !state.isBusy,
    );
  }
}

/// Serverless: Packet or Domain Fronting. Tor: bridges. MASQUE: mode. Worker / WARP: variant.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector();

  /// Domain Fronting needs its CA installed: until it exists, choosing it asks first.
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.mode == ConnectionMode.masque && state.core == CoreType.aether) {
      return ChipMenu<bool>(
        values: const [false, true],
        selected: state.device.aetherMasqueFragment,
        label: (fragment) => fragment ? 'Fragment' : 'Normal',
        onSelected: state.setAetherMasqueFragment,
        enabled: !state.isBusy,
      );
    }
    if (state.mode == ConnectionMode.masque) {
      return ChipMenu(
        values: MasqueVariant.values,
        selected: state.masqueVariant,
        label: (v) => v.label(state.profile.masque.transport == 'h3'),
        onSelected: state.setMasqueVariant,
        enabled: !state.isBusy,
      );
    }
    if (state.mode == ConnectionMode.tor) {
      // Direct, Tor's built-in bridges of a transport, or the custom bridges from Settings → Tor.
      return ChipMenu(
        values: torBridges.keys.toList(),
        selected: state.device.torBridge,
        label: (v) {
          final count = state.profile.tor.bridges.length;
          return v == 'custom' && count > 0
              ? 'Custom bridges ($count)'
              : torBridges[v] ?? v;
        },
        onSelected: state.setTorBridge,
        enabled: !state.isBusy,
      );
    }
    if (state.mode == ConnectionMode.serverless) {
      return ChipMenu(
        values: ServerlessMode.values,
        selected: state.serverlessMode,
        label: (v) => v.label,
        onSelected: state.setServerlessMode,
        enabled: !state.isBusy,
      );
    }
    return ChipMenu(
      // Browser Dialer is supported on Windows for Proxy and System Proxy.
      // TUN remains intentionally unsupported for Browser Dialer.
      values: ConnectionVariant.of(state.mode),
      selected: state.variant,
      label: (v) => v.label(state.mode),
      onSelected: state.setVariant,
      enabled: !state.isBusy,
    );
  }
}
