import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:material_symbols_icons/symbols.dart';

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
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({super.key});

  /// What the exit carries: the worker relays only TCP, Tor too; WARP, MASQUE and Psiphon also
  /// UDP; the chain proxy depends on its protocol ([ChainInfo.carries]).
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
    ExitNode.chain =>
      chain == null ? const [] : ChainInfo.of(chain.link)?.carries ?? const [],
    ExitNode.psiphon => mode == ConnectionMode.ssh
        ? const ['TCP']
        : const ['TCP', 'UDP'],
    ExitNode.tor => const ['TCP'],
  };

  static String _regionLabel(String code) => code.isEmpty
      ? 'Fastest'
      : '${countryFlag(code)} ${exitRegions[code] ?? code}';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final exit = state.exitNode;
    final isServerlessDns =
        state.mode == ConnectionMode.serverless &&
        state.serverlessMode == ServerlessMode.dns;
    // The Psiphon and Tor types have no exit node to choose: only the region can change.
    final hasExitNode =
        state.mode != ConnectionMode.psiphon &&
        state.mode != ConnectionMode.tor &&
        state.mode != ConnectionMode.aether &&
        !isServerlessDns;
    final nodes = switch (state.mode) {
      ConnectionMode.serverless => state.serverlessMode ==
              ServerlessMode.domainFronting
          ? [ExitNode.worker, ExitNode.psiphon]
          : [ExitNode.worker, ExitNode.psiphon, ExitNode.tor],
      // The chain proxy is an exit node once there's one the type can carry (Settings → Chain proxies).
      _ => [
        for (final n in ExitNode.values)
          if (n != ExitNode.chain || state.usableChains.isNotEmpty) n,
      ],
    };
    final chain = state.exitChain;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      shape: roundedShape(
        kHeroRadius,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
          width: 0.75,
        ),
      ),
      color: scheme.surfaceContainer.withValues(alpha: 0.80),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: defaultTargetPlatform == TargetPlatform.windows ? 16 : 24,
          vertical: defaultTargetPlatform == TargetPlatform.windows ? 8 : 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SettingTile(
                  label: 'Connection',
                  selector: const _TypeSelector(),
                ),
                if (state.showCoreSelector)
                  _SettingTile(
                    label: 'Core',
                    selector: ChipMenu(
                      values: CoreType.values,
                      selected: state.core,
                      label: (core) => core.label,
                      onSelected: state.setCore,
                      enabled: !state.isBusy,
                    ),
                  ),
                if (state.hasModeOption)
                  _SettingTile(
                    label: 'Mode',
                    selector: const _ModeSelector(),
                  ),
                if (hasExitNode)
                  _SettingTile(
                    label: 'Exit Node',
                    selector: ChipMenu(
                      values: nodes,
                      selected: exit,
                      label: (n) => switch (n) {
                        ExitNode.worker => 'Default',
                        ExitNode.chain => 'Chain proxy',
                        ExitNode.psiphon => 'Psiphon',
                        ExitNode.tor => 'Tor',
                      },
                      badges: (n) => _transports(n, state.mode, chain: chain),
                      onSelected: state.setExitNode,
                      enabled: !state.isBusy && nodes.length > 1,
                    ),
                  ),
                if (!isServerlessDns &&
                    (exit == ExitNode.psiphon || exit == ExitNode.tor))
                  _SettingTile(
                    label: 'Region',
                    selector: ChipMenu(
                      values: ['', ...exitRegions.keys],
                      selected: state.device.exitRegion,
                      label: _regionLabel,
                      onSelected: state.setExitRegion,
                      enabled: !state.isBusy,
                    ),
                  ),
                if (exit == ExitNode.chain && chain != null)
                  _SettingTile(
                    label: 'Chain',
                    selector: ChipMenu(
                      values: state.usableChains,
                      selected: chain,
                      label: (c) => c.name,
                      subtitleBadges: (c) =>
                          ChainInfo.of(c.link)?.tags ?? const [],
                      onSelected: state.setExitChain,
                      enabled: !state.isBusy && state.usableChains.length > 1,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact setting tile: the selected value is always visible beneath its label.
class _SettingTile extends StatelessWidget {
  final String label;
  final Widget selector;

  const _SettingTile({required this.label, required this.selector});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            width: 0.7,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerLeft,
              child: selector,
            ),
          ],
        ),
      ),
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
